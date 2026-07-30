import XCTest
@testable import TwigCore

@MainActor
final class InboxTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-test-\(UUID().uuidString)-\(name)")
    }

    private func makeLine(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    func testParseGoodLine() throws {
        let line = """
        {"id":"\(UUID().uuidString)","title":"修渲染管线","project":"mergeCook4","goal":"demo可玩","due":"2026-08-05T00:00:00Z","estimateMin":120,"source":"claude","createdAt":"2026-07-30T10:00:00Z"}
        """
        let item = InboxParser.parse(line: line)
        XCTAssertEqual(item?.title, "修渲染管线")
        XCTAssertEqual(item?.project, "mergeCook4")
        XCTAssertEqual(item?.estimateMin, 120)
        XCTAssertNil(InboxParser.parse(line: "这不是 json"))
        XCTAssertNil(InboxParser.parse(line: "{\"title\":\"缺字段\"}"))
    }

    func testImportCreatesProjectGoalTask() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let inbox = tempURL("inbox.jsonl")
        let bad = tempURL("bad.jsonl")
        let line = try makeLine([
            "id": UUID().uuidString, "title": "写单元测试", "project": "twig",
            "goal": "v0.1", "estimateMin": 60, "source": "codex",
            "createdAt": "2026-07-30T10:00:00Z",
        ])
        try line.write(to: inbox, atomically: true, encoding: .utf8)

        let report = try InboxImporter(store: store).importInbox(at: inbox, badLinesURL: bad)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.badLines, [])
        XCTAssertTrue(store.taskExists(title: "写单元测试", projectName: "twig"))
        // 收件箱已清空
        XCTAssertEqual(try String(contentsOf: inbox, encoding: .utf8), "")
    }

    func testImportSkipsDuplicatesAndArchivesBadLines() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let p = store.addProject(name: "twig", colorHint: "#D97757")
        let g = store.addGoal(to: p, title: "v0.1", horizon: .short, targetDate: nil)
        _ = store.addTask(to: g, title: "已有任务")
        let inbox = tempURL("inbox.jsonl")
        let bad = tempURL("bad.jsonl")
        let dup = try makeLine([
            "id": UUID().uuidString, "title": "已有任务", "project": "twig",
            "source": "claude", "createdAt": "2026-07-30T10:00:00Z",
        ])
        try (dup + "\n坏行\n").write(to: inbox, atomically: true, encoding: .utf8)

        let report = try InboxImporter(store: store).importInbox(at: inbox, badLinesURL: bad)
        XCTAssertEqual(report.imported, 0)
        XCTAssertEqual(report.skippedDuplicates, 1)
        XCTAssertEqual(report.badLines, ["坏行"])
        XCTAssertTrue(try String(contentsOf: bad, encoding: .utf8).contains("坏行"))
    }
}
