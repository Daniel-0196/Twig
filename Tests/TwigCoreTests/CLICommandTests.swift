import XCTest
@testable import TwigCore

final class CLICommandTests: XCTestCase {
    func testParseFullAdd() throws {
        let cmd = try CLICommandParser.parse([
            "add", "修渲染管线", "--project", "mergeCook4",
            "--goal", "demo可玩", "--due", "2026-08-05", "--estimate", "120",
        ])
        guard case .add(let title, let project, let goal, let horizon, let due, let estimate) = cmd else {
            return XCTFail("期望 add，得到 \(cmd)")
        }
        XCTAssertEqual(title, "修渲染管线")
        XCTAssertEqual(project, "mergeCook4")
        XCTAssertEqual(goal, "demo可玩")
        XCTAssertNil(horizon)
        XCTAssertEqual(estimate, 120)
        XCTAssertNotNil(due)
    }

    func testParseHorizon() throws {
        let cmd = try CLICommandParser.parse([
            "add", "定版交互", "--project", "twig", "--goal", "v0.5", "--horizon", "mid",
        ])
        guard case .add(_, _, let goal, let horizon, _, _) = cmd else {
            return XCTFail("期望 add")
        }
        XCTAssertEqual(goal, "v0.5")
        XCTAssertEqual(horizon, "mid")
        XCTAssertThrowsError(try CLICommandParser.parse([
            "add", "x", "--project", "p", "--horizon", "medium",
        ]))
    }

    func testParseMinimalAdd() throws {
        let cmd = try CLICommandParser.parse(["add", "随手记", "--project", "twig"])
        guard case .add(_, _, let goal, let horizon, let due, let estimate) = cmd else {
            return XCTFail("期望 add")
        }
        XCTAssertNil(goal); XCTAssertNil(horizon); XCTAssertNil(due); XCTAssertNil(estimate)
    }

    func testParseList() throws {
        XCTAssertEqual(try CLICommandParser.parse(["list"]), .list(project: nil))
        XCTAssertEqual(try CLICommandParser.parse(["list", "--project", "twig"]), .list(project: "twig"))
    }

    func testErrors() {
        XCTAssertThrowsError(try CLICommandParser.parse([]))
        XCTAssertThrowsError(try CLICommandParser.parse(["add"]))
        XCTAssertThrowsError(try CLICommandParser.parse(["add", "x"]))               // 缺 --project
        XCTAssertThrowsError(try CLICommandParser.parse(["add", "x", "--project"]))   // 缺值
        XCTAssertThrowsError(try CLICommandParser.parse(["frobnicate"]))
        XCTAssertThrowsError(try CLICommandParser.parse(["add", "x", "--project", "p", "--due", "8月5日"]))
    }
}
