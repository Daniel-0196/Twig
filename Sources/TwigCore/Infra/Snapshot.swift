import Foundation

public struct TaskSnapshot: Codable {
    public var generatedAt: Date
    public var projects: [ProjectSnapshot]
}

public struct ProjectSnapshot: Codable {
    public var name: String
    public var colorHint: String
    public var goals: [GoalSnapshot]
}

public struct GoalSnapshot: Codable {
    public var title: String
    public var horizon: String
    public var tasks: [TaskLine]
}

public struct TaskLine: Codable {
    public var title: String
    public var isDone: Bool
}

public enum SnapshotExporter {
    public static func export(projects: [Project], to url: URL) throws {
        let snapshot = TaskSnapshot(generatedAt: Date(), projects: projects.map { p in
            ProjectSnapshot(name: p.name, colorHint: p.colorHint, goals: p.goals
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { g in
                    GoalSnapshot(title: g.title, horizon: g.horizon.rawValue, tasks: g.tasks
                        .sorted { $0.sortOrder < $1.sortOrder }
                        .map { TaskLine(title: $0.title, isDone: $0.isDone) })
                })
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
