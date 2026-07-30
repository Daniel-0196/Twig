import SwiftUI
import SwiftData
import TwigCore

/// 今日 / 本周：TimeEntry 聚合 + 已完成任务
struct ReportsView: View {
    let appState: AppState
    @State private var scope = 0   // 0=今日 1=本周

    var body: some View {
        VStack {
            Picker("", selection: $scope) {
                Text("今日").tag(0)
                Text("本周").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            let ctx = appState.container.mainContext
            let entries = (try? ctx.fetch(FetchDescriptor<TimeEntry>())) ?? []
            let tasks = (try? ctx.fetch(FetchDescriptor<TwigCore.Task>())) ?? []

            if scope == 0 {
                let report = ReportAggregator.dayReport(day: Date(), entries: entries, tasks: tasks)
                DayReportCard(report: report)
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
}

struct DayReportCard: View {
    let report: DayReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                VStack { Text("\(report.focusMinutes)").font(.largeTitle); Text("专注分钟").font(.caption) }
                VStack { Text("\(report.breakMinutes)").font(.largeTitle); Text("休息分钟").font(.caption) }
                VStack { Text("\(report.completedTaskTitles.count)").font(.largeTitle); Text("完成任务").font(.caption) }
            }
            if !report.perProjectFocus.isEmpty {
                Divider()
                ForEach(report.perProjectFocus.sorted(by: { $0.value > $1.value }), id: \.key) { name, minutes in
                    HStack {
                        Text(name)
                        Spacer()
                        Text("\(minutes) 分钟").foregroundStyle(.secondary)
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
