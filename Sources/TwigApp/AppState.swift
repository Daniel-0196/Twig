import AppKit
import Foundation
import SwiftData
import TwigCore
import UserNotifications

/// 悬浮窗两态：树画板（默认）/ 折叠横条
enum WidgetMode {
    case tree, folded
}

@MainActor
@Observable
final class AppState {
    let container: ModelContainer
    let taskStore: TaskStore
    let timerStore: TimerStore
    var widgetMode: WidgetMode = .tree
    /// TreeCanvasView 布局后回写的节点包围盒尺寸，TreeWidgetController 据此扩窗
    var reportedTreeBounds: CGSize = CGSize(width: 720, height: 400)
    var openMainWindow: (() -> Void)?

    /// 引擎状态的 @Observable 镜像：TimerStore/PomodoroEngine 不可观察，
    /// MenuBarExtra / 横条读这里才能随状态变化刷新（由 timerStore.onStateChange 回写）
    private(set) var engineState: EngineState = .idle
    /// pendingCompletionCheck 的镜像（"任务完成了吗？"横条确认按钮的显示开关）
    private(set) var pendingCompletionCheck = false

    private var snapshotTimer: Timer?

    init() {
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
        seedDefaultEdges()
        repairChainsThroughHiddenGoals()
        recoverUnclosedEntries()
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
        case .idle:
            // 原型行为：idle 时显示当前任务（第一个未完成任务 · 目标名）
            if let task = taskStore.firstIncompleteTask() {
                if let goal = task.goal { return "\(task.title) · \(goal.title)" }
                return task.title
            }
            return "全部完成 🎉"
        case .focusing: return "专注中"
        case .onBreak(_, _, let isLong): return isLong ? "长休息" : "短休息"
        }
    }

    func exportSnapshot() {
        try? SnapshotExporter.export(projects: taskStore.allProjects(), to: TwigPaths.snapshotURL)
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
    /// 松手瞬间的 treeOffset（回弹动画起点，由 TreeCanvasView.endPull 记录）
    var springStartOffset: CGSize = .zero
    /// 节点拖动中锁定悬停（HoverHud 尊重它：拖动时隐藏 HUD）
    var hoverLockedForDrag = false
    /// 悬停 HUD ＋按下：在该节点附近内联输入新节点（输入卡由 TreeCanvasView 渲染）
    var addingNodeNear: Goal?
    /// 叶子点击：任务详情弹卡（task + 所属 goal），TaskLeafPopover 读取
    var leafTask: (TwigCore.Task, Goal)?
    /// 光标在悬浮窗内容坐标系（左上角原点）的位置，不在窗内为 nil。
    /// 非激活 NSPanel 收不到 SwiftUI onHover，悬停 HUD 由 TreeCanvasView 每帧轮询这里驱动；
    /// 由 TreeWidgetController.start 注入（闭包避免 AppState 反向持有窗口）
    var widgetMouseProvider: (() -> CGPoint?)?

    /// 画布数据修订号：TreeCanvasView 在 body 里读它。
    /// SwiftData 模型属性变更会被 @Observable 跟踪，但"插入/删除 Goal、增删 Edge"
    /// 这类 fetch 结果集变化不会触发视图失效——这些方法里手动递增驱动画布重渲染
    private(set) var canvasRevision = 0
    private func bumpCanvas() { canvasRevision &+= 1 }

    func goalsAndEdges() -> (goals: [Goal], edges: [Edge]) {
        let ctx = container.mainContext
        let all = (try? ctx.fetch(FetchDescriptor<Goal>())) ?? []
        let edges = (try? ctx.fetch(FetchDescriptor<Edge>())) ?? []
        // 画板只放目标节点；收件箱默认落点（历史"收集箱"/新"未分配"）不是阶段目标，不上树。
        // 边必须同步过滤：隐藏节点混在顺序链里时，布局的深度/frontier 遍历会把它
        // 当隐形节点排进画布——节点卡不渲染（被过滤），茎线却照着位置画，
        // 看起来就是"从横条垂一条长线 / 断在半空"
        let hidden: Set<String> = ["收集箱", "未分配"]
        let goals = all.filter { !hidden.contains($0.title) }
        let ids = Set(goals.map(\.persistentModelID))
        let canvasEdges = edges.filter {
            ($0.from.map { ids.contains($0.persistentModelID) } ?? false)
                && ($0.to.map { ids.contains($0.persistentModelID) } ?? false)
        }
        return (goals, canvasEdges)
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
            bumpCanvas()
        }
    }

    func toggleEdgeType(_ edge: Edge) {
        edge.type = edge.type == .sequence ? .reference : .sequence
        try? container.mainContext.save()
        bumpCanvas()
    }

    func deleteGoalTree(_ goal: Goal) {
        // 番茄挂在这棵树的任务上：先正常停止（保留已计时段），否则 activeTask 悬挂读已删模型会 trap
        if let active = timerStore.activeTask, active.goal?.persistentModelID == goal.persistentModelID {
            timerStore.releaseIfActive(active)
        }
        // 同理由：详情弹卡 / 内联输入卡不能继续引用已删目标
        if leafTask?.1.persistentModelID == goal.persistentModelID { leafTask = nil }
        if addingNodeNear?.persistentModelID == goal.persistentModelID { addingNodeNear = nil }
        container.mainContext.delete(goal)   // 边级联删除
        try? container.mainContext.save()
        bumpCanvas()
        exportSnapshot()
    }

    @discardableResult
    func addGoalNode(near: Goal, title: String) -> Goal? {
        guard let project = near.project else { return nil }
        let goal = taskStore.addGoal(to: project, title: title, horizon: near.horizon, targetDate: nil)
        bumpCanvas()
        exportSnapshot()
        return goal
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

    /// 一次性迁移：老库没有 Edge 数据（收件箱导入只建任务），树画板一条茎线都画不出来。
    /// 为"目标 ≥2 且完全无边"的项目按 sortOrder 补默认顺序链（同原型默认数据）；
    /// 用户手动删过边的项目（曾经有线）不重补，只做一轮
    private func seedDefaultEdges() {
        let flag = "twig.seededDefaultEdges.v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let ctx = container.mainContext
        let edges = (try? ctx.fetch(FetchDescriptor<Edge>())) ?? []
        var touched = false
        for p in taskStore.allProjects() {
            let goals = p.goals.sorted { $0.sortOrder < $1.sortOrder }
            guard goals.count > 1 else { continue }
            let ids = Set(goals.map(\.persistentModelID))
            let hasEdge = edges.contains {
                ($0.from.map { ids.contains($0.persistentModelID) } ?? false)
                    || ($0.to.map { ids.contains($0.persistentModelID) } ?? false)
            }
            guard !hasEdge else { continue }
            for i in 0..<(goals.count - 1) {
                ctx.insert(Edge(type: .sequence, from: goals[i], to: goals[i + 1]))
            }
            touched = true
        }
        if touched { try? ctx.save() }
    }

    /// v2 迁移：v1 建链时把"收集箱"也串进了顺序链。画板过滤收集箱后链条断裂——
    /// 断点两侧的目标都成入度 0 的根，全部横排成一行（看起来就是"方向不对"）。
    /// 修复：绕过隐藏目标重接链（p→收集箱→s 变 p→s），清掉触碰隐藏目标的边，
    /// 空壳隐藏目标直接删除；再对仍无边的项目按 v1 规则补链（v1 之后才建的项目漏补）
    private func repairChainsThroughHiddenGoals() {
        let flag = "twig.repairedHiddenGoalChains.v2"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let ctx = container.mainContext
        let hidden: Set<String> = ["收集箱", "未分配"]
        guard let allEdges = try? ctx.fetch(FetchDescriptor<Edge>()) else { return }
        var touched = false
        for p in taskStore.allProjects() {
            let ids = Set(p.goals.map(\.persistentModelID))
            let edges = allEdges.filter {
                ($0.from.map { ids.contains($0.persistentModelID) } ?? false)
                    || ($0.to.map { ids.contains($0.persistentModelID) } ?? false)
            }
            // 1) 绕过隐藏目标重接链（先快照，循环内可能删除收集箱本体）
            for h in p.goals.filter({ hidden.contains($0.title) }) {
                let ins = edges.filter { $0.type == .sequence && $0.to?.persistentModelID == h.persistentModelID }
                let outs = edges.filter { $0.type == .sequence && $0.from?.persistentModelID == h.persistentModelID }
                if let up = ins.first?.from, let down = outs.first?.to,
                   up.persistentModelID != down.persistentModelID {
                    let dup = allEdges.contains {
                        $0.type == .sequence
                            && $0.from?.persistentModelID == up.persistentModelID
                            && $0.to?.persistentModelID == down.persistentModelID
                    }
                    if !dup { ctx.insert(Edge(type: .sequence, from: up, to: down)); touched = true }
                }
                for e in ins + outs { ctx.delete(e); touched = true }
                // 空壳隐藏目标删除（有任务的保留，仍按标题过滤不上树）
                if h.tasks.isEmpty { ctx.delete(h); touched = true }
            }
            // 2) 仍无边的可见目标 ≥2：按 sortOrder 补默认链（收集箱已剔除，不会再串进链里）
            let visible = p.goals
                .filter { !hidden.contains($0.title) && !$0.isDeleted }
                .sorted { $0.sortOrder < $1.sortOrder }
            let visibleEdges = allEdges.filter {
                $0.type == .sequence
                    && ($0.from.map { f in visible.contains(where: { $0.persistentModelID == f.persistentModelID }) } ?? false)
                    && ($0.to.map { t in visible.contains(where: { $0.persistentModelID == t.persistentModelID }) } ?? false)
            }
            if visible.count > 1 && visibleEdges.isEmpty {
                for i in 0..<(visible.count - 1) {
                    ctx.insert(Edge(type: .sequence, from: visible[i], to: visible[i + 1]))
                }
                touched = true
            }
        }
        if touched { try? ctx.save(); bumpCanvas() }
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
