import Foundation
import SwiftData

@MainActor
public final class TimerStore {
    public private(set) var engine: PomodoroEngine
    public private(set) var activeTask: Task?
    public private(set) var pendingCompletionCheck = false
    public var onEvent: ((EngineEvent) -> Void)?

    public let container: ModelContainer
    private var ctx: ModelContext { container.mainContext }
    private var activeEntry: TimeEntry?
    private let now: () -> Date

    public init(container: ModelContainer,
                config: TimerConfig = .load(),
                now: @escaping () -> Date = Date.init) {
        self.container = container
        self.now = now
        self.engine = PomodoroEngine(config: config, now: now)
    }

    public func start(task: Task?, mode: TimerMode) {
        if let stale = activeEntry {   // 保险：旧段直接丢弃
            ctx.delete(stale)
            activeEntry = nil
        }
        engine.startFocus(mode: mode)
        activeTask = task
        let entry = TimeEntry(kind: mode == .stopwatch ? .stopwatch : .pomodoro, startedAt: now())
        entry.task = task
        ctx.insert(entry)
        activeEntry = entry
        try? ctx.save()
    }

    public func tick() {
        heartbeat()
        guard let event = engine.tick() else { return }
        handle(event)
    }

    public func stop(discard: Bool) {
        guard let event = engine.stop(discard: discard) else { return }
        if discard, let entry = activeEntry {
            ctx.delete(entry)
        } else {
            activeEntry?.endedAt = now()
        }
        activeEntry = nil
        activeTask = nil
        try? ctx.save()
        onEvent?(event)
    }

    public func finishFocus() {
        guard let event = engine.finishFocusEarly() else { return }
        handle(event)
    }

    public func endBreak() {
        guard let event = engine.endBreak() else { return }
        closeActiveEntry()
        try? ctx.save()
        onEvent?(event)
    }

    public func heartbeat() {
        guard let entry = activeEntry, entry.endedAt == nil else { return }
        entry.lastHeartbeat = now()
        try? ctx.save()
    }

    /// 番茄结束后的"任务完成了吗？"：markTaskDone=true 则勾掉当前任务
    public func dismissCompletionCheck(markTaskDone: Bool) {
        if markTaskDone, let task = activeTask {
            task.isDone = true
            task.completedAt = now()
        }
        if case .focusing = engine.state {} else { activeTask = nil }
        pendingCompletionCheck = false
        try? ctx.save()
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .focusCompleted:
            closeActiveEntry()
            pendingCompletionCheck = true
            if case .onBreak(let startedAt, _, _) = engine.state {
                let breakEntry = TimeEntry(kind: .break, startedAt: startedAt)
                ctx.insert(breakEntry)
                activeEntry = breakEntry
            }
        case .breakCompleted:
            closeActiveEntry()
        case .stopped:
            break
        }
        try? ctx.save()
        onEvent?(event)
    }

    private func closeActiveEntry() {
        guard let entry = activeEntry, entry.endedAt == nil else { return }
        entry.endedAt = now()
        activeEntry = nil
    }
}
