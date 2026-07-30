import AppKit
import SwiftUI
import TwigCore

/// 中间栏：目标泳道（短/中/长期）+ 该项目近期 git 提交
struct TimelineView: View {
    let appState: AppState
    let project: Project
    @State private var commits: [GitCommit] = []
    @State private var repoLost = false
    @State private var newGoalTitle = ""
    @State private var newGoalHorizon: Horizon = .short

    var body: some View {
        List {
            ForEach(Horizon.allCases, id: \.self) { horizon in
                Section(horizonLabel(horizon)) {
                    ForEach(goals(for: horizon), id: \.persistentModelID) { goal in
                        GoalRow(appState: appState, goal: goal)
                    }
                }
            }
            Section("近期提交") {
                if project.repoPath == nil {
                    Button("绑定本地 git 仓库…") { pickRepo() }
                } else if repoLost {
                    Label("仓库失联：路径不存在或已不是 git 仓库", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("重新选择…") { pickRepo() }
                } else {
                    ForEach(commits, id: \.hash) { commit in
                        HStack {
                            Text(commit.hash).font(.caption.monospaced())
                            Text(commit.subject).lineLimit(1)
                            Spacer()
                            Text(commit.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(project.name)
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("新目标", text: $newGoalTitle)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $newGoalHorizon) {
                    Text("短期").tag(Horizon.short)
                    Text("中期").tag(Horizon.mid)
                    Text("长期").tag(Horizon.long)
                }
                .frame(width: 90)
                Button("添加目标") {
                    guard !newGoalTitle.isEmpty else { return }
                    appState.taskStore.addGoal(to: project, title: newGoalTitle,
                                               horizon: newGoalHorizon, targetDate: nil)
                    newGoalTitle = ""
                    appState.exportSnapshot()
                }
            }
            .padding(10)
        }
        .onAppear(perform: loadCommits)
    }

    private func goals(for horizon: Horizon) -> [Goal] {
        project.goals
            .filter { $0.horizon == horizon }
            .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
    }

    private func horizonLabel(_ h: Horizon) -> String {
        switch h { case .short: "短期"; case .mid: "中期"; case .long: "长期" }
    }

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            project.repoPath = url.path
            try? appState.container.mainContext.save()
            loadCommits()
        }
    }

    private func loadCommits() {
        guard let path = project.repoPath else { return }
        do {
            commits = try GitReader().log(repoPath: path,
                                          since: Date().addingTimeInterval(-14 * 86400))
            repoLost = false
        } catch {
            repoLost = true
            commits = []
        }
    }
}

/// 目标行：勾选 + 其下任务
struct GoalRow: View {
    let appState: AppState
    let goal: Goal
    @State private var newTaskTitle = ""

    var body: some View {
        DisclosureGroup {
            ForEach(goal.tasks.sorted { $0.sortOrder < $1.sortOrder }, id: \.persistentModelID) { task in
                HStack {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange)
                    Text(task.title).strikethrough(task.isDone)
                    Spacer()
                    if let estimate = task.estimateMin {
                        Text("约\(estimate)分钟").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("专注") {
                        appState.timerStore.start(task: task, mode: .pomodoro)
                    }
                    .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.taskStore.toggleTask(task)
                    appState.exportSnapshot()
                }
            }
            HStack {
                TextField("新任务", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newTaskTitle.isEmpty else { return }
                    appState.taskStore.addTask(to: goal, title: newTaskTitle)
                    newTaskTitle = ""
                    appState.exportSnapshot()
                }
            }
        } label: {
            HStack {
                Text(goal.title).font(.headline)
                Spacer()
                if let date = goal.targetDate {
                    Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
