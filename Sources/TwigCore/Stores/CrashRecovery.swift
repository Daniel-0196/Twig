import Foundation

public enum CrashRecovery {
    /// 上次运行未闭合的计时（崩溃/强退/断电的痕迹）
    public static func openEntries(_ entries: [TimeEntry]) -> [TimeEntry] {
        entries.filter { $0.endedAt == nil }
    }

    /// 补记：以最后一次心跳为准（我们最多只丢一分钟）
    public static func close(_ entry: TimeEntry, fallback now: Date) {
        let end = min(entry.lastHeartbeat, now)
        entry.endedAt = max(end, entry.startedAt)
    }
}
