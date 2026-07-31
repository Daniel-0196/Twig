import XCTest
@testable import TwigCore

@MainActor
final class SnapshotTests: XCTestCase {
    func testExportWritesReadableSnapshot() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "v0.1", horizon: .short, targetDate: nil)
        _ = store.addTask(to: g, title: "任务A")
        let done = store.addTask(to: g, title: "任务B")
        store.toggleTask(done)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-snap-\(UUID().uuidString).json")
        try SnapshotExporter.export(projects: store.allProjects(), to: url)

        let data = try Data(contentsOf: url)
        let snap = try JSONDecoder().decode(TaskSnapshot.self, from: data)
        XCTAssertEqual(snap.projects.count, 1)
        XCTAssertEqual(snap.projects[0].name, "twig")
        XCTAssertEqual(snap.projects[0].goals[0].tasks.map(\.title), ["任务A", "任务B"])
        XCTAssertFalse(snap.projects[0].goals[0].tasks[0].isDone)
        XCTAssertTrue(snap.projects[0].goals[0].tasks[1].isDone)
    }
}
