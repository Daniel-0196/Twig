import XCTest
@testable import TwigCore

@MainActor
final class TreeTopologyTests: XCTestCase {
    // 拓扑函数只读 Goal/Edge 的引用关系，直接构造即可（不需 insert）
    private func goals(_ titles: [String]) -> [Goal] {
        titles.map { Goal(title: $0, horizon: .short, targetDate: nil) }
    }
    private func link(_ a: Goal, _ b: Goal) -> Edge { Edge(type: .sequence, from: a, to: b) }

    func testDepthsFromRoots() {
        let g = goals(["v0.2", "v0.5", "v1.0", "孤立"])
        let edges = [link(g[0], g[1]), link(g[1], g[2])]
        let d = TreeTopology.depths(goals: g, edges: edges)
        XCTAssertEqual(d[g[0].persistentModelID], 0)
        XCTAssertEqual(d[g[1].persistentModelID], 1)
        XCTAssertEqual(d[g[2].persistentModelID], 2)
        XCTAssertEqual(d[g[3].persistentModelID], -1)   // 孤立
    }

    func testFanOutDepths() {
        // 一出多：两个子节点同深度
        let g = goals(["根", "子A", "子B", "孙"])
        let edges = [link(g[0], g[1]), link(g[0], g[2]), link(g[1], g[3])]
        let d = TreeTopology.depths(goals: g, edges: edges)
        XCTAssertEqual(d[g[1].persistentModelID], 1)
        XCTAssertEqual(d[g[2].persistentModelID], 1)
        XCTAssertEqual(d[g[3].persistentModelID], 2)
    }

    func testComponentBidirectional() {
        let g = goals(["a", "b", "c", "x"])
        let edges = [link(g[0], g[1]), link(g[1], g[2])]
        let comp = TreeTopology.component(of: g[1], edges: edges)
        XCTAssertEqual(comp.ids.count, 3)
        XCTAssertEqual(comp.depths[g[0].persistentModelID], 1)
        XCTAssertEqual(comp.depths[g[1].persistentModelID], 0)
        XCTAssertEqual(comp.depths[g[2].persistentModelID], 1)
        XCTAssertFalse(comp.ids.contains(g[3].persistentModelID))
    }

    func testSanitizeRevealPullsAncestorsUp() {
        let g = goals(["a", "b", "c"])
        let edges = [link(g[0], g[1]), link(g[1], g[2])]
        g[0].revealed = true
        g[2].revealed = true   // c 出土但 b 没有 → b 必须被强制出土
        TreeTopology.sanitizeReveal(goals: g, edges: edges)
        XCTAssertTrue(g[1].revealed)
    }

    func testIsRoot() {
        let g = goals(["a", "b"])
        let edges = [link(g[0], g[1])]
        XCTAssertTrue(TreeTopology.isRoot(g[0], edges: edges))
        XCTAssertFalse(TreeTopology.isRoot(g[1], edges: edges))
    }
}
