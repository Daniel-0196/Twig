import Foundation
import SwiftData

public enum TimeKind: String, Codable {
    case pomodoro, stopwatch, `break`
}

@Model
public final class TimeEntry {
    public var kind: TimeKind
    public var startedAt: Date
    public var endedAt: Date?
    public var lastHeartbeat: Date
    public var task: Task?

    public init(kind: TimeKind, startedAt: Date) {
        self.kind = kind
        self.startedAt = startedAt
        self.lastHeartbeat = startedAt
    }

    /// 实际时长（秒）；未闭合时按 lastHeartbeat 估算
    public var duration: TimeInterval {
        (endedAt ?? lastHeartbeat).timeIntervalSince(startedAt)
    }
}
