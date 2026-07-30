import Foundation

public enum TimerMode: Equatable {
    case pomodoro, stopwatch, countdown(minutes: Int)
}

public enum EngineState: Equatable {
    case idle
    case focusing(startedAt: Date, plannedEnd: Date?, mode: TimerMode)
    case onBreak(startedAt: Date, endsAt: Date, isLong: Bool)
}

public enum EngineEvent: Equatable {
    case focusCompleted(duration: TimeInterval)
    case breakCompleted
    case stopped(recorded: TimeInterval?)   // nil = 已丢弃
}

public final class PomodoroEngine {
    public private(set) var state: EngineState = .idle
    public private(set) var completedPomodoros: Int = 0
    public var config: TimerConfig
    private let now: () -> Date

    public init(config: TimerConfig = TimerConfig(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    @discardableResult
    public func startFocus(mode: TimerMode) -> EngineState {
        let started = now()
        let plannedEnd: Date?
        switch mode {
        case .stopwatch: plannedEnd = nil
        case .pomodoro: plannedEnd = started.addingTimeInterval(TimeInterval(config.focusMinutes * 60))
        case .countdown(let m): plannedEnd = started.addingTimeInterval(TimeInterval(m * 60))
        }
        state = .focusing(startedAt: started, plannedEnd: plannedEnd, mode: mode)
        return state
    }

    @discardableResult
    public func tick() -> EngineEvent? {
        switch state {
        case .focusing(_, let plannedEnd, _):
            guard let plannedEnd, now() >= plannedEnd else { return nil }
            return completeFocus(endedAt: plannedEnd)
        case .onBreak(_, let endsAt, _):
            guard now() >= endsAt else { return nil }
            state = .idle
            return .breakCompleted
        case .idle:
            return nil
        }
    }

    @discardableResult
    public func finishFocusEarly() -> EngineEvent? {
        guard case .focusing(let startedAt, _, _) = state else { return nil }
        return completeFocus(endedAt: max(now(), startedAt))
    }

    @discardableResult
    public func stop(discard: Bool) -> EngineEvent? {
        guard case .focusing(let startedAt, _, _) = state else { return nil }
        state = .idle
        if discard { return .stopped(recorded: nil) }
        return .stopped(recorded: now().timeIntervalSince(startedAt))
    }

    @discardableResult
    public func endBreak() -> EngineEvent? {
        guard case .onBreak = state else { return nil }
        state = .idle
        return .breakCompleted
    }

    private func completeFocus(endedAt: Date) -> EngineEvent {
        guard case .focusing(let startedAt, _, _) = state else { return .stopped(recorded: nil) }
        completedPomodoros += 1
        let isLong = completedPomodoros % config.pomodorosPerLongBreak == 0
        if config.autoStartBreak {
            let mins = isLong ? config.longBreakMinutes : config.shortBreakMinutes
            state = .onBreak(startedAt: endedAt,
                             endsAt: endedAt.addingTimeInterval(TimeInterval(mins * 60)),
                             isLong: isLong)
        } else {
            state = .idle
        }
        return .focusCompleted(duration: endedAt.timeIntervalSince(startedAt))
    }
}
