import XCTest
import SwiftData
@testable import TwigCore

@MainActor
final class ModelTests: XCTestCase {
    func testProjectGoalTaskChainPersists() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let project = Project(name: "mergeCook4", colorHint: "#D97757")
        ctx.insert(project)
        let goal = Goal(title: "demo 可玩", horizon: .short, targetDate: nil)
        goal.project = project
        ctx.insert(goal)
        let task = Task(title: "修 shader 编译错误")
        task.goal = goal
        ctx.insert(task)
        try ctx.save()

        let projects = try ctx.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects[0].goals.count, 1)
        XCTAssertEqual(projects[0].goals[0].tasks.first?.title, "修 shader 编译错误")
        XCTAssertFalse(projects[0].goals[0].tasks[0].isDone)
    }

    func testCascadeDeleteRemovesGoalsAndTasks() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let project = Project(name: "p", colorHint: "#5F8A6E")
        ctx.insert(project)
        let goal = Goal(title: "g", horizon: .mid, targetDate: nil)
        goal.project = project
        ctx.insert(goal)
        let task = Task(title: "t")
        task.goal = goal
        ctx.insert(task)
        try ctx.save()

        ctx.delete(project)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Goal>()), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Task>()), 0)
    }

    func testTimeEntryDefaults() throws {
        let entry = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertNil(entry.endedAt)
        XCTAssertEqual(entry.lastHeartbeat, entry.startedAt)
        XCTAssertEqual(entry.kind, .pomodoro)
    }
}
