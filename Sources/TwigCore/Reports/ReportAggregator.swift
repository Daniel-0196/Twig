import Foundation

public struct DayReport: Equatable {
    public var day: Date
    public var focusMinutes: Int = 0
    public var breakMinutes: Int = 0
    public var completedTaskTitles: [String] = []
    public var perProjectFocus: [String: Int] = [:]   // 项目名 → 专注分钟
}

public enum ReportAggregator {
    public static func dayReport(day: Date, entries: [TimeEntry], tasks: [Task],
                                 calendar: Calendar = .current) -> DayReport {
        var report = DayReport(day: calendar.startOfDay(for: day))
        for entry in entries where calendar.isDate(entry.startedAt, inSameDayAs: day) {
            let minutes = Int(entry.duration / 60)
            switch entry.kind {
            case .pomodoro, .stopwatch:
                report.focusMinutes += minutes
                if let name = entry.task?.goal?.project?.name {
                    report.perProjectFocus[name, default: 0] += minutes
                }
            case .break:
                report.breakMinutes += minutes
            }
        }
        report.completedTaskTitles = tasks
            .filter { $0.isDone && $0.completedAt.map({ calendar.isDate($0, inSameDayAs: day) }) ?? false }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            .map(\.title)
        return report
    }

    /// 包含 day 的那一周（周一到周日）7 天报表
    public static func weekReport(containing day: Date, entries: [TimeEntry], tasks: [Task],
                                  calendar input: Calendar = .current) -> [DayReport] {
        var calendar = input
        calendar.firstWeekday = 2   // 周一
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day) else { return [] }
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return dayReport(day: date, entries: entries, tasks: tasks, calendar: calendar)
        }
    }
}
