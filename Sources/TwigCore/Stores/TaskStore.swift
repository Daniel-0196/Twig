import Foundation
import SwiftData

@MainActor
public final class TaskStore {
    public let container: ModelContainer
    private var ctx: ModelContext { container.mainContext }
    private static let orderStep: Double = 1024

    public init(container: ModelContainer) {
        self.container = container
    }

    @discardableResult
    public func addProject(name: String, colorHint: String, repoPath: String? = nil) -> Project {
        let p = Project(name: name, colorHint: colorHint, repoPath: repoPath)
        ctx.insert(p)
        try? ctx.save()
        return p
    }

    @discardableResult
    public func addGoal(to project: Project, title: String, horizon: Horizon, targetDate: Date?) -> Goal {
        let next = (project.goals.map(\.sortOrder).max() ?? 0) + Self.orderStep
        let g = Goal(title: title, horizon: horizon, targetDate: targetDate, sortOrder: next)
        g.project = project
        ctx.insert(g)
        try? ctx.save()
        return g
    }

    @discardableResult
    public func addTask(to goal: Goal, title: String, estimateMin: Int? = nil, dueDate: Date? = nil) -> Task {
        let next = (goal.tasks.map(\.sortOrder).max() ?? 0) + Self.orderStep
        let t = Task(title: title, estimateMin: estimateMin, dueDate: dueDate, sortOrder: next)
        t.goal = goal
        ctx.insert(t)
        try? ctx.save()
        return t
    }

    public func toggleTask(_ task: Task) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        try? ctx.save()
    }

    /// 今日任务 = 未完成 且（无截止日期 或 截止不晚于今天结束）
    public func tasksForToday(on day: Date, calendar: Calendar = .current) -> [Task] {
        let endOfDay = calendar.startOfDay(for: day).addingTimeInterval(86400)
        return incompleteTasks()
            .filter { $0.dueDate.map { $0 < endOfDay } ?? true }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    public func incompleteTasks() -> [Task] {
        (try? ctx.fetch(FetchDescriptor<Task>()))?.filter { !$0.isDone } ?? []
    }

    public func allProjects() -> [Project] {
        (try? ctx.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    public func taskExists(title: String, projectName: String) -> Bool {
        incompleteTasks().contains {
            $0.title == title && $0.goal?.project?.name == projectName
        }
    }

    public func findOrCreateProject(named name: String) -> Project {
        if let existing = allProjects().first(where: { $0.name == name }) { return existing }
        return addProject(name: name, colorHint: Self.defaultColor)
    }

    public func findOrCreateGoal(in project: Project, title: String, horizon: Horizon = .short) -> Goal {
        if let existing = project.goals.first(where: { $0.title == title }) { return existing }
        return addGoal(to: project, title: title, horizon: horizon, targetDate: nil)
    }

    private static let defaultColor = "#D97757"
}
