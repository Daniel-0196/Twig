import Foundation
import SwiftData

@MainActor
public final class TimerStore {
    public private(set) var engine: PomodoroEngine
    public private(set) var activeTask: Task?
    public private(set) var pendingCompletionCheck = false
    public var onEvent: ((EngineEvent) -> Void)?
    /// 引擎状态/待确认标记变化后回调（AppState 用它同步 @Observable 镜像，菜单/横条才能刷新）
    public var onStateChange: (() -> Void)?

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
        if case .focusing = engine.state {
            // 进行中的计时不能被静默丢弃：先正常停止（保留旧段）再开始新段
            stop(discard: false)
        } else if let stale = activeEntry {
            // 兜底：引擎不在专注中却残留未闭合 entry（异常状态），清掉
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
        onStateChange?()
    }

    public func tick() {
        heartbeat()
        guard let event = engine.tick() else { return }
        handle(event)
    }

    /// 删除任务（或其所属目标树）前的守卫：进行中的番茄正常停止（保留已计时段）；
    /// 休息态 engine.stop 是 no-op，activeTask 会悬挂指向已删模型（读属性即 trap），故直接摘掉
    public func releaseIfActive(_ task: Task) {
        guard activeTask?.persistentModelID == task.persistentModelID else { return }
        stop(discard: false)
        if activeTask != nil {
            activeTask = nil
            pendingCompletionCheck = false
            onStateChange?()
        }
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
        onStateChange?()
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
        onStateChange?()
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
        onStateChange?()
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
        onStateChange?()
    }

    private func closeActiveEntry() {
        guard let entry = activeEntry, entry.endedAt == nil else { return }
        entry.endedAt = now()
        activeEntry = nil
    }
}
