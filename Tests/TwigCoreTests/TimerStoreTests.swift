import XCTest
import SwiftData
@testable import TwigCore

@MainActor
final class TimerStoreTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() throws -> TimerStore {
        TimerStore(container: try TwigStore.makeContainer(inMemory: true),
                   config: TimerConfig(),
                   now: { [unowned self] in self.now })
    }

    func testCompletedPomodoroWritesClosedEntryAndOpensBreak() throws {
        let store = try makeStore()
        var events: [EngineEvent] = []
        store.onEvent = { events.append($0) }
        store.start(task: nil, mode: .pomodoro)
        now = now.addingTimeInterval(25 * 60)
        store.tick()
        XCTAssertTrue(events.contains(.focusCompleted(duration: 25 * 60)))
        let entries = try store.container.mainContext.fetch(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(entries.count, 2)   // 1 段专注（已闭合）+ 1 段休息（进行中）
        let focus = entries.first { $0.kind == .pomodoro }
        XCTAssertNotNil(focus?.endedAt)
        XCTAssertEqual(focus?.duration ?? 0, 25 * 60, accuracy: 2)
        XCTAssertEqual(entries.first { $0.kind == .break }?.endedAt, nil)
        XCTAssertTrue(store.pendingCompletionCheck)
    }

    func testStopDiscardDeletesEntry() throws {
        let store = try makeStore()
        store.start(task: nil, mode: .stopwatch)
        now = now.addingTimeInterval(300)
        store.stop(discard: true)
        let count = try store.container.mainContext.fetchCount(FetchDescriptor<TimeEntry>())
        XCTAssertEqual(count, 0)
    }

    func testHeartbeatUpdatesTimestamp() throws {
        let store = try makeStore()
        store.start(task: nil, mode: .stopwatch)
        now = now.addingTimeInterval(60)
        store.heartbeat()
        let entry = try store.container.mainContext.fetch(FetchDescriptor<TimeEntry>()).first
        XCTAssertEqual(entry?.lastHeartbeat, now)
    }

    func testDismissCompletionCheckCanMarkTaskDone() throws {
        let store = try makeStore()
        let taskStore = TaskStore(container: store.container)
        let p = taskStore.addProject(name: "twig", colorHint: "#D97757")
        let g = taskStore.addGoal(to: p, title: "g", horizon: .short, targetDate: nil)
        let t = taskStore.addTask(to: g, title: "被计时的任务")
        store.start(task: t, mode: .pomodoro)
        now = now.addingTimeInterval(25 * 60)
        store.tick()
        store.dismissCompletionCheck(markTaskDone: true)
        XCTAssertFalse(store.pendingCompletionCheck)
        XCTAssertTrue(t.isDone)
    }
}
