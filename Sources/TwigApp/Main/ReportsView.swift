import SwiftUI
import SwiftData
import TwigCore

/// 今日 / 本周：TimeEntry 聚合 + 已完成任务；支持按项目切换范围
struct ReportsView: View {
    let appState: AppState
    @Binding var scopeProject: String?   // nil = 全部项目；否则项目名
    @State private var scope = 0   // 0=今日 1=本周

    var body: some View {
        VStack {
            Picker("范围", selection: $scopeProject) {
                Text("全部项目").tag(String?.none)
                ForEach(appState.taskStore.allProjects(), id: \.persistentModelID) { project in
                    Text(project.name).tag(String?.some(project.name))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)

            Picker("", selection: $scope) {
                Text("今日").tag(0)
                Text("本周").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            let ctx = appState.container.mainContext
            let allEntries = (try? ctx.fetch(FetchDescriptor<TimeEntry>())) ?? []
            let allTasks = (try? ctx.fetch(FetchDescriptor<TwigCore.Task>())) ?? []
            let entries = scopeProject == nil ? allEntries
                : allEntries.filter { $0.task?.goal?.project?.name == scopeProject }
            let tasks = scopeProject == nil ? allTasks
                : allTasks.filter { $0.goal?.project?.name == scopeProject }

            if scope == 0 {
                let report = ReportAggregator.dayReport(day: Date(), entries: entries, tasks: tasks)
                DayReportCard(report: report,
                              breakdownTitle: scopeProject == nil ? "分项目专注" : "分目标专注",
                              breakdown: focusBreakdown(entries: entries))
            } else {
                let week = ReportAggregator.weekReport(containing: Date(), entries: entries, tasks: tasks)
                List(week, id: \.day) { report in
                    HStack {
                        Text(report.day, format: .dateTime.month().day().weekday())
                        Spacer()
                        Text("专注 \(report.focusMinutes) 分钟")
                        Text("完成 \(report.completedTaskTitles.count) 项")
                            .foregroundStyle(.secondary)
                    }
                }
                let total = week.reduce(0) { $0 + $1.focusMinutes }
                Text("本周共专注 \(total / 60) 小时 \(total % 60) 分钟")
                    .font(.headline)
                    .padding()
            }
            Spacer()
        }
    }

    /// 今日专注分布：全部范围按项目聚合；单项目范围按目标聚合
    private func focusBreakdown(entries: [TimeEntry]) -> [(name: String, minutes: Int)] {
        let calendar = Calendar.current
        var minutes: [String: Int] = [:]
        for entry in entries where calendar.isDate(entry.startedAt, inSameDayAs: Date()) {
            guard entry.kind == .pomodoro || entry.kind == .stopwatch else { continue }
            let key = scopeProject == nil
                ? entry.task?.goal?.project?.name
                : entry.task?.goal?.title
            if let key {
                minutes[key, default: 0] += Int(entry.duration / 60)
            }
        }
        return minutes.sorted { $0.value > $1.value }.map { (name: $0.key, minutes: $0.value) }
    }
}

struct DayReportCard: View {
    let report: DayReport
    var breakdownTitle: String = "分项目专注"
    var breakdown: [(name: String, minutes: Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                VStack { Text("\(report.focusMinutes)").font(.largeTitle); Text("专注分钟").font(.caption) }
                VStack { Text("\(report.breakMinutes)").font(.largeTitle); Text("休息分钟").font(.caption) }
                VStack { Text("\(report.completedTaskTitles.count)").font(.largeTitle); Text("完成任务").font(.caption) }
            }
            if !breakdown.isEmpty {
                Divider()
                Text(breakdownTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(breakdown, id: \.name) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text("\(item.minutes) 分钟").foregroundStyle(.secondary)
                    }
                }
            }
            if !report.completedTaskTitles.isEmpty {
                Divider()
                ForEach(report.completedTaskTitles, id: \.self) { title in
                    Label(title, systemImage: "checkmark.circle")
                }
            }
            Spacer()
        }
        .padding()
    }
}
