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
        // 收件箱已清空（rename 流程：文件被处理掉；兜底 truncate 流程：内容为空）
        let remaining = (try? String(contentsOf: inbox, encoding: .utf8)) ?? ""
        XCTAssertEqual(remaining, "")
    }

    /// #1 回归：连续两轮 写入→导入→再写入→再导入，第二轮的行必须被导入。
    /// 旧实现用 atomic write 清空收件箱（inode 被替换），配合文件监视器第二轮起永久失效。
    func testSecondRoundAppendIsImported() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let inbox = tempURL("inbox.jsonl")
        let bad = tempURL("bad.jsonl")
        let importer = InboxImporter(store: store)

        let line1 = try makeLine([
            "id": UUID().uuidString, "title": "第一轮任务", "project": "twig",
            "source": "cli", "createdAt": "2026-07-30T10:00:00Z",
        ])
        try (line1 + "\n").write(to: inbox, atomically: true, encoding: .utf8)
        XCTAssertEqual(try importer.importInbox(at: inbox, badLinesURL: bad).imported, 1)

        // 模拟 CLI 追加：文件已被处理掉则重建（与 twig-cli 的 append-or-create 一致）
        let line2 = try makeLine([
            "id": UUID().uuidString, "title": "第二轮任务", "project": "twig",
            "source": "cli", "createdAt": "2026-07-30T11:00:00Z",
        ])
        if FileManager.default.fileExists(atPath: inbox.path),
           let handle = try? FileHandle(forWritingTo: inbox) {
            handle.seekToEndOfFile()
            handle.write(Data((line2 + "\n").utf8))
            try? handle.close()
        } else {
            try (line2 + "\n").write(to: inbox, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try importer.importInbox(at: inbox, badLinesURL: bad).imported, 1)
        XCTAssertTrue(store.taskExists(title: "第二轮任务", projectName: "twig"))
    }

    /// #5：导入先把 inbox 原子 rename 为 processing 文件，处理完删除——
    /// read→清空之间 CLI 追加的行落在重建的新 inbox 里，不会被误清。
    func testImportRenamesToProcessingAndCleansUp() throws {
        let store = TaskStore(container: try TwigStore.makeContainer(inMemory: true))
        let inbox = tempURL("inbox.jsonl")
        let processing = inbox.deletingPathExtension().appendingPathExtension("processing.jsonl")
        let bad = tempURL("bad.jsonl")
        let line = try makeLine([
            "id": UUID().uuidString, "title": "任务", "project": "twig",
            "source": "cli", "createdAt": "2026-07-30T10:00:00Z",
        ])
        try (line + "\n").write(to: inbox, atomically: true, encoding: .utf8)

        _ = try InboxImporter(store: store).importInbox(at: inbox, badLinesURL: bad)
        XCTAssertFalse(FileManager.default.fileExists(atPath: processing.path),
                       "processing 文件处理完必须删除")
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
