import Foundation
import TwigCore

do {
    switch try CLICommandParser.parse(Array(CommandLine.arguments.dropFirst())) {
    case .add(let title, let project, let goal, let due, let estimate):
        try FileManager.default.createDirectory(at: TwigPaths.supportDir, withIntermediateDirectories: true)
        let item = InboxItem(title: title, project: project, goal: goal,
                             due: due, estimateMin: estimate, source: "cli")
        let line = try InboxParser.encode(item) + "\n"
        if FileManager.default.fileExists(atPath: TwigPaths.inboxURL.path),
           let handle = try? FileHandle(forWritingTo: TwigPaths.inboxURL) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try line.write(to: TwigPaths.inboxURL, atomically: true, encoding: .utf8)
        }
        print("已加入 Twig 收件箱：\(title) → \(project)")

    case .list(let projectFilter):
        guard let data = FileManager.default.contents(atPath: TwigPaths.snapshotURL.path) else {
            print("还没有快照（Twig.app 运行过一次后才会有）。收件箱里的任务会在下次启动 app 时导入。")
            exit(0)
        }
        let snapshot = try JSONDecoder().decode(TaskSnapshot.self, from: data)
        for project in snapshot.projects where projectFilter == nil || project.name == projectFilter {
            print("◆ \(project.name)")
            for goal in project.goals {
                print("  ○ \(goal.title) [\(goal.horizon)]")
                for task in goal.tasks {
                    print("    \(task.isDone ? "☑" : "☐") \(task.title)")
                }
            }
        }

    case .help:
        print(CLICommandParser.usage)
    }
} catch let error as CLIUsageError {
    FileHandle.standardError.write(Data((error.description + "\n").utf8))
    exit(1)
}
