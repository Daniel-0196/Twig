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

    private var inboxWatcher: DispatchSourceFileSystemObject?
    private var snapshotTimer: Timer?
    private(set) var lastImportReport: ImportReport?

    init() {
        do {
            container = try TwigStore.makeContainer()
        } catch {
            fatalError("数据库打开失败：\(error.localizedDescription)")
        }
        taskStore = TaskStore(container: container)
        timerStore = TimerStore(container: container)
    }

    func start() {
        try? StoreBackup.backupNow()
        recoverUnclosedEntries()
        importInbox()
        watchInbox()
        exportSnapshot()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in self?.exportSnapshot() }
        }
        timerStore.onEvent = { [weak self] event in self?.handleEngineEvent(event) }
    }

    var currentFocusTitle: String {
        if let task = timerStore.activeTask { return task.title }
        switch timerStore.engine.state {
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

    // MARK: - 私有

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
        try? FileManager.default.createDirectory(at: TwigPaths.supportDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: TwigPaths.inboxURL.path) {
            FileManager.default.createFile(atPath: TwigPaths.inboxURL.path, contents: nil)
        }
        let fd = open(TwigPaths.inboxURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            _Concurrency.Task { @MainActor in self?.importInbox() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        inboxWatcher = source
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
