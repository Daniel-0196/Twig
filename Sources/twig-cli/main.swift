import Foundation
import TwigCore

// twig CLI：直接读写数据库（收件箱机制已移除）
// TaskStore 是 @MainActor（mainContext 隔离），CLI 里用 RunLoop 驱动 MainActor 队列

@MainActor
func run() throws {
    let container = try TwigStore.makeContainer()
    let store = TaskStore(container: container)

    switch try CLICommandParser.parse(Array(CommandLine.arguments.dropFirst())) {
    case .add(let title, let project, let goal, let horizon, let due, let estimate):
        let p = store.findOrCreateProject(named: project)
        let g = store.findOrCreateGoal(in: p, title: goal ?? "未分配",
                                       horizon: horizon.flatMap { Horizon(rawValue: $0) } ?? .short)
        _ = store.addTask(to: g, title: title, estimateMin: estimate, dueDate: due)
        print("已加入 Twig：\(title) → \(project)")

    case .list(let projectFilter):
        for project in store.allProjects() where projectFilter == nil || project.name == projectFilter {
            print("◆ \(project.name)")
            for goal in project.goals.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                print("  ○ \(goal.title) [\(goal.horizon.rawValue)]")
                for task in goal.tasks.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    print("    \(task.isDone ? "☑" : "☐") \(task.title)")
                }
            }
        }

    case .help:
        print(CLICommandParser.usage)
    }
}

// 驱动 MainActor 队列（run() 完成前一直跑 RunLoop）
let mainTask = _Concurrency.Task { @MainActor in
    do {
        try run()
        exit(0)
    } catch let error as CLIUsageError {
        FileHandle.standardError.write(Data((error.description + "\n").utf8))
        exit(1)
    } catch {
        FileHandle.standardError.write(Data(("错误：\(error.localizedDescription)\n").utf8))
        exit(1)
    }
}
_ = mainTask
RunLoop.main.run()
