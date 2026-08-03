import AppKit
import Foundation
import SwiftData
import TwigCore
import UserNotifications

enum WidgetState {
    case collapsed, peeked, expanded
}

@MainActor
@Observable
final class AppState {
    let container: ModelContainer
    let taskStore: TaskStore
    let timerStore: TimerStore
    var widgetState: WidgetState = .collapsed
    var openMainWindow: (() -> Void)?

    /// 枝干方向（用户可自定义，存 UserDefaults 键 twig.branchDirection）
    var branchDirection: BranchDirection {
        didSet { UserDefaults.standard.set(branchDirection.rawValue, forKey: "twig.branchDirection") }
    }

    /// BranchView 布局后回写，供窗口扩容器使用
    var branchContentSize: CGSize = CGSize(width: 560, height: 360)

    /// 引擎状态的 @Observable 镜像：TimerStore/PomodoroEngine 不可观察，
    /// MenuBarExtra / 横条读这里才能随状态变化刷新（由 timerStore.onStateChange 回写）
    private(set) var engineState: EngineState = .idle
    /// pendingCompletionCheck 的镜像（"任务完成了吗？"横条确认按钮的显示开关）
    private(set) var pendingCompletionCheck = false

    /// 枝干布局参数（全部可调——交互手感迭代就改这里）
    var branchTuning: BranchTuning {
        var tuning = BranchTuning()
        tuning.direction = branchDirection
        return tuning
    }

    private var inboxWatcher: DispatchSourceFileSystemObject?
    private var snapshotTimer: Timer?
    private(set) var lastImportReport: ImportReport?

    init() {
        let raw = UserDefaults.standard.string(forKey: "twig.branchDirection")
        branchDirection = raw.flatMap { BranchDirection(rawValue: $0) } ?? .right
        // 先备份再打开/迁移数据库（spec §10）：迁移失败尚有备份可回滚
        try? StoreBackup.backupNow()
        do {
            container = try TwigStore.makeContainer()
        } catch {
            let alert = NSAlert()
            alert.messageText = "数据库损坏"
            alert.informativeText = "无法打开数据库（\(error.localizedDescription)）。启动前的备份保留在 \(TwigPaths.backupsDir.path)，把备份目录里的 twig.store* 复制回 \(TwigPaths.supportDir.path) 即可回滚。"
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
            fatalError("数据库打开失败：\(error.localizedDescription)")
        }
        taskStore = TaskStore(container: container)
        timerStore = TimerStore(container: container)
    }

    func start() {
        migrateRevealFlags()
        recoverUnclosedEntries()
        watchInbox()
        handleInboxWrite()
        exportSnapshot()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.exportSnapshot() }
        }
        timerStore.onEvent = { [weak self] event in self?.handleEngineEvent(event) }
        timerStore.onStateChange = { [weak self] in self?.syncEngineMirror() }
        syncEngineMirror()
    }

    private func syncEngineMirror() {
        if engineState != timerStore.engine.state { engineState = timerStore.engine.state }
        if pendingCompletionCheck != timerStore.pendingCompletionCheck {
            pendingCompletionCheck = timerStore.pendingCompletionCheck
        }
    }

    var currentFocusTitle: String {
        if let task = timerStore.activeTask { return task.title }
        switch engineState {
        case .idle: return "点我开始专注"
        case .focusing: return "专注中"
        case .onBreak(_, _, let isLong): return isLong ? "长休息" : "短休息"
        }
    }

    func importInbox() {
        let report = try? InboxImporter(store: taskStore)
            .importInbox(at: TwigPaths.inboxURL, badLinesURL: TwigPaths.badLinesURL)
        if let report, report.imported > 0 || !report.badLines.isEmpty {
            lastImportReport = report
            exportSnapshot()
        }
    }

    func exportSnapshot() {
        try? SnapshotExporter.export(projects: taskStore.allProjects(), to: TwigPaths.snapshotURL)
    }

    /// 枝干节点上下拖动 = 调整该目标在项目内的排期：
    /// 布局按 targetDate 排序，所以与拖动方向上的相邻目标交换 targetDate / sortOrder，
    /// 松手后枝干顺序随之变化（nodeID 由 BranchLayout.stableID 派生，这里反查找回 goal）
    func moveGoal(nodeID: UUID, verticalDelta: CGFloat) {
        let steps = Int((verticalDelta / 64).rounded())   // 每 64pt 一格
        guard steps != 0 else { return }
        for project in taskStore.allProjects() {
            let goals = project.goals.filter { !$0.isDone }
                .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
            guard goals.count > 1,
                  let index = goals.firstIndex(where: { BranchLayout.stableID(for: $0) == nodeID }) else { continue }
            let newIndex = min(max(index + steps, 0), goals.count - 1)
            guard newIndex != index else { return }
            let dragged = goals[index]
            let neighbor = goals[newIndex]
            swap(&dragged.targetDate, &neighbor.targetDate)
            swap(&dragged.sortOrder, &neighbor.sortOrder)
            try? container.mainContext.save()
            return
        }
    }

    /// 由枝干节点 ID 反查 Goal（nodeID 由 BranchLayout.stableID 派生，与 moveGoal 同一套反查）
    func goal(forNodeID nodeID: UUID) -> Goal? {
        for project in taskStore.allProjects() {
            for goal in project.goals where BranchLayout.stableID(for: goal) == nodeID {
                return goal
            }
        }
        return nil
    }

    /// 枝干悬停面板用：该目标下未完成任务（按排序，最多 limit 条）
    func openTasks(forNodeID nodeID: UUID, limit: Int = 5) -> [TwigCore.Task] {
        guard let goal = goal(forNodeID: nodeID) else { return [] }
        return goal.tasks
            .filter { !$0.isDone }
            .sorted { $0.sortOrder < $1.sortOrder }
            .prefix(limit)
            .map { $0 }
    }

    /// 枝干悬停面板用：给节点对应的目标加任务
    func addTask(toNodeID nodeID: UUID, title: String) {
        guard let goal = goal(forNodeID: nodeID) else { return }
        taskStore.addTask(to: goal, title: title)
        exportSnapshot()
    }

    /// 枝干面板用：开始专注该目标（取第一个未完成任务；没有则不计名计时）
    func startFocus(onNodeID nodeID: UUID) {
        let task = openTasks(forNodeID: nodeID, limit: 1).first
        timerStore.start(task: task, mode: .pomodoro)
        widgetState = .collapsed
    }

    /// 枝干面板用：开始专注具体任务
    func startFocus(on task: TwigCore.Task) {
        timerStore.start(task: task, mode: .pomodoro)
        widgetState = .collapsed
    }

    // MARK: - 拔树画板状态
    var pullDirection: PullDirection = {
        if let raw = UserDefaults.standard.string(forKey: "twig.pullDirection"),
           let d = PullDirection(rawValue: raw) { return d }
        return .down
    }() {
        didSet { UserDefaults.standard.set(pullDirection.rawValue, forKey: "twig.pullDirection") }
    }
    var pullSession: PullSession?
    var pullComponent: Set<PersistentIdentifier> = []
    var pullDepths: [PersistentIdentifier: Int] = [:]
    var pullProject: Project?
    var hoveredGoal: Goal?
    var treeOffset: CGSize = .zero

    func goalsAndEdges() -> (goals: [Goal], edges: [Edge]) {
        let ctx = container.mainContext
        let goals = (try? ctx.fetch(FetchDescriptor<Goal>())) ?? []
        let edges = (try? ctx.fetch(FetchDescriptor<Edge>())) ?? []
        return (goals, edges)
    }

    func placements(in rect: CGRect) -> [PersistentIdentifier: CGPoint] {
        let (goals, edges) = goalsAndEdges()
        return TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: pullDirection)
    }

    func reveal(_ goal: Goal) {
        goal.revealed = true
        let (goals, edges) = goalsAndEdges()
        TreeTopology.sanitizeReveal(goals: goals, edges: edges)
        try? container.mainContext.save()
        exportSnapshot()
    }

    func setCustomPosition(_ goal: Goal, x: CGFloat, y: CGFloat) {
        goal.customX = x
        goal.customY = y
        try? container.mainContext.save()
    }

    func resetTree(_ project: Project) {
        for g in project.goals {
            g.revealed = (g.horizon == .short)
            g.customX = nil
            g.customY = nil
        }
        treeOffset = .zero
        try? container.mainContext.save()
        exportSnapshot()
    }

    func addEdge(from: Goal, to: Goal) {
        guard from.persistentModelID != to.persistentModelID else { return }
        let (_, edges) = goalsAndEdges()
        let dup = edges.contains {
            $0.type == .sequence
            && $0.from?.persistentModelID == from.persistentModelID
            && $0.to?.persistentModelID == to.persistentModelID
        }
        if !dup {
            container.mainContext.insert(Edge(type: .sequence, from: from, to: to))
            try? container.mainContext.save()
        }
    }

    func toggleEdgeType(_ edge: Edge) {
        edge.type = edge.type == .sequence ? .reference : .sequence
        try? container.mainContext.save()
    }

    func deleteGoalTree(_ goal: Goal) {
        container.mainContext.delete(goal)   // 边级联删除
        try? container.mainContext.save()
        exportSnapshot()
    }

    func addGoalNode(near: Goal, title: String) {
        guard let project = near.project else { return }
        taskStore.addGoal(to: project, title: title, horizon: near.horizon, targetDate: nil)
        exportSnapshot()
    }

    // MARK: - 私有

    /// 迁移：首次升级后，为短期目标补 revealed=true
    private func migrateRevealFlags() {
        let ctx = container.mainContext
        guard let all = try? ctx.fetch(FetchDescriptor<Goal>()) else { return }
        var touched = false
        for g in all where g.horizon == .short && !g.revealed {
            g.revealed = true
            touched = true
        }
        if touched { try? ctx.save() }
    }

    private func recoverUnclosedEntries() {
        let ctx = container.mainContext
        guard let all = try? ctx.fetch(FetchDescriptor<TimeEntry>()) else { return }
        let open = CrashRecovery.openEntries(all)
        guard !open.isEmpty else { return }
        for entry in open { CrashRecovery.close(entry, fallback: Date()) }
        try? ctx.save()
        let total = Int(open.reduce(0) { $0 + $1.duration } / 60)
        let alert = NSAlert()
        alert.messageText = "补记中断的计时"
        alert.informativeText = "检测到 \(open.count) 段未正常结束的计时（共约 \(total) 分钟），已按最后心跳补记。如不需要可在主窗口删除对应记录。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func watchInbox() {
        inboxWatcher?.cancel()
        inboxWatcher = nil
        try? FileManager.default.createDirectory(at: TwigPaths.supportDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: TwigPaths.inboxURL.path) {
            FileManager.default.createFile(atPath: TwigPaths.inboxURL.path, contents: nil)
        }
        let fd = open(TwigPaths.inboxURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            _Concurrency.Task { @MainActor in self?.handleInboxWrite() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        inboxWatcher = source
    }

    /// 收件箱写入事件：导入 → 重建监视 → 补漏，循环到收件箱为空。
    /// 导入会把 inbox 原子 rename 成 processing 文件处理掉（丢数据窗口修复），
    /// 之后 inbox 由 CLI 重建——inode 已换，旧 fd 的 O_EVTONLY 监视永远不再触发，
    /// 所以每轮导入后必须 re-arm；re-arm 间隙 CLI 又写入的，靠文件大小检查兜底再导一轮。
    private func handleInboxWrite() {
        for _ in 0..<8 {
            importInbox()
            watchInbox()
            let size = (try? FileManager.default
                .attributesOfItem(atPath: TwigPaths.inboxURL.path)[.size] as? Int) ?? 0
            if size == 0 { return }
        }
    }

    private func handleEngineEvent(_ event: EngineEvent) {
        let config = timerStore.engine.config
        switch event {
        case .focusCompleted:
            if config.notificationsEnabled { notify(title: "专注结束", body: "任务完成了吗？去横条上确认一下") }
            if config.soundEnabled { NSSound(named: NSSound.Name("Glass"))?.play() }
        case .breakCompleted:
            if config.notificationsEnabled { notify(title: "休息结束", body: "回来继续吧") }
        case .stopped:
            break
        }
    }

    private func notify(title: String, body: String) {
        // 未打包为 .app（swift build 直跑）时 UserNotifications 无 bundle 可用，跳过
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
