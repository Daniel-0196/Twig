import XCTest
import CoreGraphics
@testable import TwigCore

final class TreeLayoutTests: XCTestCase {
    private let rect = CGRect(x: 100, y: 100, width: 800, height: 500)

    private func makeProject() -> (Project, [Goal], [Edge]) {
        let p = Project(name: "twig", colorHint: "#D97757")
        let a = Goal(title: "v0.2", horizon: .short, targetDate: nil)
        let b = Goal(title: "v0.5", horizon: .mid, targetDate: nil)
        let c = Goal(title: "v1.0", horizon: .long, targetDate: nil)
        [a, b, c].forEach { $0.project = p }
        let edges = [Edge(type: .sequence, from: a, to: b), Edge(type: .sequence, from: b, to: c)]
        return (p, [a, b, c], edges)
    }

    func testUpDirectionRootNearBottomBuriedBelow() {
        let (p, goals, edges) = makeProject()
        goals[0].revealed = true   // 只出土根
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .up)
        let rootY = pos[goals[0].persistentModelID]!.y
        XCTAssertEqual(rootY, rect.maxY - 90, accuracy: 1)   // 贴底边
        let buriedY = pos[goals[1].persistentModelID]!.y
        XCTAssertGreaterThan(buriedY, rect.maxY)             // 埋在底边外
        XCTAssertEqual(pos.count, 3)
        _ = p
    }

    func testRootMigratesWithRevealDepth() {
        let (_, goals, edges) = makeProject()
        goals[0].revealed = true
        goals[1].revealed = true   // 出土到 depth 1
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .up)
        let rootY = pos[goals[0].persistentModelID]!.y
        // rootBase = soil − max(90, 1×190+50) = bottom − 240
        XCTAssertEqual(rootY, rect.maxY - 240, accuracy: 1)
        // v0.5 在根与土壤之间（链条朝土壤连续）
        let midY = pos[goals[1].persistentModelID]!.y
        XCTAssertGreaterThan(midY, rootY)
        XCTAssertLessThan(midY, rect.maxY)
    }

    func testDownDirectionMirrored() {
        let (_, goals, edges) = makeProject()
        goals[0].revealed = true
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .down)
        let rootY = pos[goals[0].persistentModelID]!.y
        XCTAssertEqual(rootY, rect.minY + 90, accuracy: 1)
        XCTAssertLessThan(pos[goals[1].persistentModelID]!.y, rect.minY)   // 埋在顶边外
    }

    func testSiblingFanOut() {
        let p = Project(name: "twig", colorHint: "#D97757")
        let root = Goal(title: "root", horizon: .short, targetDate: nil)
        let k1 = Goal(title: "k1", horizon: .mid, targetDate: nil)
        let k2 = Goal(title: "k2", horizon: .mid, targetDate: nil)
        [root, k1, k2].forEach { $0.project = p; $0.revealed = true }
        let edges = [Edge(type: .sequence, from: root, to: k1), Edge(type: .sequence, from: root, to: k2)]
        let pos = TreeLayout.place(goals: [root, k1, k2], edges: edges, rect: rect, direction: .up)
        let x1 = pos[k1.persistentModelID]!.x
        let x2 = pos[k2.persistentModelID]!.x
        XCTAssertNotEqual(x1, x2)   // 兄弟扇开不重叠
        XCTAssertEqual((x1 + x2) / 2, pos[root.persistentModelID]!.x, accuracy: 30)   // 以父为中心
    }

    func testCustomPositionWins() {
        let (_, goals, edges) = makeProject()
        goals[0].revealed = true
        goals[0].customX = 333; goals[0].customY = 222
        let pos = TreeLayout.place(goals: goals, edges: edges, rect: rect, direction: .up)
        XCTAssertEqual(pos[goals[0].persistentModelID], CGPoint(x: 333, y: 222))
    }
}

// MARK: - 多项目分组（mergeCook4 节点丢失回归：两项目的根都必须进画布）
final class TreeLayoutMultiProjectTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 800, height: 500)

    func testBothProjectRootsAppear() {
        let p1 = Project(name: "MergeCook", colorHint: "#7D9B76")
        let g1 = Goal(title: "渲染管线重构", horizon: .short, targetDate: nil)
        g1.project = p1; g1.revealed = true
        let p2 = Project(name: "Merge2", colorHint: "#6B8FC4")
        let g2 = Goal(title: "玩法闭环", horizon: .short, targetDate: nil)
        g2.project = p2; g2.revealed = true
        let pos = TreeLayout.place(goals: [g1, g2], edges: [], rect: rect, direction: .down)
        // 两个根都排进画布，且按项目分列（baseCross 相距 260）
        let x1 = pos[g1.persistentModelID]!.x
        let x2 = pos[g2.persistentModelID]!.x
        XCTAssertEqual(pos.count, 2)
        XCTAssertEqual(abs(x2 - x1), 260, accuracy: 45)   // 列距 260 ± 抖动22
        XCTAssertEqual(pos[g1.persistentModelID]!.y, rect.minY + 90, accuracy: 1)
        XCTAssertEqual(pos[g2.persistentModelID]!.y, rect.minY + 90, accuracy: 1)
    }
}
