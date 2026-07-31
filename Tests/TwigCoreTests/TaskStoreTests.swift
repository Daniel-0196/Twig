import XCTest
@testable import TwigCore

@MainActor
final class TaskStoreTests: XCTestCase {
    private func makeStore() throws -> TaskStore {
        TaskStore(container: try TwigStore.makeContainer(inMemory: true))
    }

    func testAddAndToggleTask() throws {
        let store = try makeStore()
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "v0.1", horizon: .short, targetDate: nil)
        let t = store.addTask(to: g, title: "写 TaskStore")
        XCTAssertFalse(t.isDone)
        store.toggleTask(t)
        XCTAssertTrue(t.isDone)
        XCTAssertNotNil(t.completedAt)
        store.toggleTask(t)
        XCTAssertFalse(t.isDone)
        XCTAssertNil(t.completedAt)
    }

    func testTasksForTodayIncludesOverdueButNotFuture() throws {
        let store = try makeStore()
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "g", horizon: .short, targetDate: nil)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        _ = store.addTask(to: g, title: "昨天就该做", dueDate: yesterday)
        _ = store.addTask(to: g, title: "今天的", dueDate: today)
        _ = store.addTask(to: g, title: "明天的", dueDate: tomorrow)
        let done = store.addTask(to: g, title: "已完成", dueDate: today)
        store.toggleTask(done)
        let titles = store.tasksForToday(on: today).map(\.title)
        XCTAssertEqual(Set(titles), ["昨天就该做", "今天的"])
    }

    func testFindOrCreateIsIdempotent() throws {
        let store = try makeStore()
        let p1 = store.findOrCreateProject(named: "twig")
        let p2 = store.findOrCreateProject(named: "twig")
        XCTAssertEqual(p1.persistentModelID, p2.persistentModelID)
        let g1 = store.findOrCreateGoal(in: p1, title: "收集箱")
        let g2 = store.findOrCreateGoal(in: p1, title: "收集箱")
        XCTAssertEqual(g1.persistentModelID, g2.persistentModelID)
        XCTAssertEqual(store.allProjects().count, 1)
    }

    func testTaskExistsChecksIncompleteOnly() throws {
        let store = try makeStore()
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "g", horizon: .short, targetDate: nil)
        let t = store.addTask(to: g, title: "修内存泄漏")
        XCTAssertTrue(store.taskExists(title: "修内存泄漏", projectName: "twig"))
        store.toggleTask(t)
        XCTAssertFalse(store.taskExists(title: "修内存泄漏", projectName: "twig"))
    }
}
