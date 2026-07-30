import XCTest
@testable import TwigCore

final class ReportTests: XCTestCase {
    private let calendar = Calendar.current

    private func entry(_ kind: TimeKind, start: Date, minutes: Double) -> TimeEntry {
        let e = TimeEntry(kind: kind, startedAt: start)
        e.endedAt = start.addingTimeInterval(minutes * 60)
        return e
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testDayReportSumsFocusAndBreak() {
        let today = day(2026, 7, 30)
        let entries = [
            entry(.pomodoro, start: day(2026, 7, 30, 9), minutes: 25),
            entry(.stopwatch, start: day(2026, 7, 30, 14), minutes: 50),
            entry(.break, start: day(2026, 7, 30, 10), minutes: 5),
            entry(.pomodoro, start: day(2026, 7, 29, 9), minutes: 25),  // 昨天不算
        ]
        let report = ReportAggregator.dayReport(day: today, entries: entries, tasks: [])
        XCTAssertEqual(report.focusMinutes, 75)
        XCTAssertEqual(report.breakMinutes, 5)
    }

    func testCrossMidnightEntryCountsToStartDay() {
        let night = day(2026, 7, 30, 23)
        let entries = [entry(.pomodoro, start: night, minutes: 60)]   // 跨到 31 号
        let d30 = ReportAggregator.dayReport(day: day(2026, 7, 30), entries: entries, tasks: [])
        let d31 = ReportAggregator.dayReport(day: day(2026, 7, 31), entries: entries, tasks: [])
        XCTAssertEqual(d30.focusMinutes, 60)
        XCTAssertEqual(d31.focusMinutes, 0)
    }

    func testCompletedTasksAndPerProjectFocus() {
        let today = day(2026, 7, 30)
        let project = Project(name: "twig", colorHint: "#D97757")
        let goal = Goal(title: "v0.1", horizon: .short, targetDate: nil)
        goal.project = project
        let task = Task(title: "完成的任务")
        task.goal = goal
        task.isDone = true
        task.completedAt = day(2026, 7, 30, 16)
        let other = Task(title: "昨天完成的")
        other.isDone = true
        other.completedAt = day(2026, 7, 29, 16)

        let focus = entry(.pomodoro, start: day(2026, 7, 30, 9), minutes: 25)
        focus.task = task

        let report = ReportAggregator.dayReport(day: today, entries: [focus], tasks: [task, other])
        XCTAssertEqual(report.completedTaskTitles, ["完成的任务"])
        XCTAssertEqual(report.perProjectFocus["twig"], 25)
    }

    func testWeekReportReturnsSevenDays() {
        let entries = [entry(.pomodoro, start: day(2026, 7, 29, 10), minutes: 25)]
        // 2026-07-30 是周四
        let week = ReportAggregator.weekReport(containing: day(2026, 7, 30), entries: entries, tasks: [])
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.reduce(0) { $0 + $1.focusMinutes }, 25)
    }
}
