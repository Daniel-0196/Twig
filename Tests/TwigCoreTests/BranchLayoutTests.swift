import XCTest
@testable import TwigCore

final class BranchLayoutTests: XCTestCase {
    private func makeProjects() -> [Project] {
        let p1 = Project(name: "渲染", colorHint: "#D97757")
        let soon = Goal(title: "demo", horizon: .short,
                        targetDate: Date().addingTimeInterval(5 * 86400), sortOrder: 1024)
        soon.project = p1
        let later = Goal(title: "优化", horizon: .mid,
                         targetDate: Date().addingTimeInterval(40 * 86400), sortOrder: 2048)
        later.project = p1
        p1.goals = [later, soon]   // 故意乱序，布局应按日期排

        let p2 = Project(name: "玩法", colorHint: "#5F8A6E")
        let g = Goal(title: "闭环", horizon: .mid,
                     targetDate: Date().addingTimeInterval(30 * 86400), sortOrder: 1024)
        g.project = p2
        p2.goals = [g]
        return [p1, p2]
    }

    func testNodesSortedByDateWithinProject() {
        let result = BranchLayout.compute(projects: makeProjects(), anchor: CGPoint(x: 0, y: 200))
        let renderNodes = result.nodes.filter { $0.colorHex == "#D97757" }
        XCTAssertEqual(renderNodes.count, 2)
        XCTAssertEqual(renderNodes[0].title, "demo")   // 日期近的排前（y 更小）
        XCTAssertLessThan(renderNodes[0].center.y, renderNodes[1].center.y)
    }

    func testFartherProjectIsMoreTransparent() {
        let result = BranchLayout.compute(projects: makeProjects(), anchor: CGPoint(x: 0, y: 200))
        let first = result.nodes.filter { $0.colorHex == "#D97757" }.map(\.opacity).max()!
        let second = result.nodes.filter { $0.colorHex == "#5F8A6E" }.map(\.opacity).max()!
        XCTAssertGreaterThan(first, second)
        XCTAssertGreaterThanOrEqual(second, 0.3)
    }

    func testMidLongTermNodesAreDashed() {
        let result = BranchLayout.compute(projects: makeProjects(), anchor: CGPoint(x: 0, y: 200))
        let demo = result.nodes.first { $0.title == "demo" }
        let closed = result.nodes.first { $0.title == "闭环" }
        XCTAssertEqual(demo?.dashed, false)
        XCTAssertEqual(closed?.dashed, true)
    }

    func testEdgesConnectAnchorToNodes() {
        let anchor = CGPoint(x: 0, y: 200)
        let result = BranchLayout.compute(projects: makeProjects(), anchor: anchor)
        XCTAssertFalse(result.edges.isEmpty)
        XCTAssertTrue(result.edges.contains { $0.from == anchor })
        // 每条边的终点都落在某个节点中心
        for edge in result.edges {
            XCTAssertTrue(result.nodes.contains { $0.center == edge.to } || edge.to == anchor)
        }
    }

    func testDirectionChangesMainAxis() {
        let anchor = CGPoint(x: 400, y: 300)
        var tuning = BranchTuning()

        tuning.direction = .right
        let right = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(right.nodes.allSatisfy { $0.center.x > anchor.x })

        tuning.direction = .left
        let left = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(left.nodes.allSatisfy { $0.center.x < anchor.x })

        tuning.direction = .down
        let down = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(down.nodes.allSatisfy { $0.center.y > anchor.y })
        XCTAssertGreaterThan(down.contentSize.height, down.contentSize.width - 400)  // 纵向布局更高

        tuning.direction = .up
        let up = BranchLayout.compute(projects: makeProjects(), anchor: anchor, tuning: tuning)
        XCTAssertTrue(up.nodes.allSatisfy { $0.center.y < anchor.y })
    }

    func testStableIDSameGoalSameNodeID() {
        let projects = makeProjects()
        let a = BranchLayout.compute(projects: projects, anchor: .zero)
        let b = BranchLayout.compute(projects: projects, anchor: CGPoint(x: 100, y: 100))
        // 同一 goal 多次布局要拿到同一个 id，否则 SwiftUI 动画会跳
        XCTAssertEqual(Set(a.nodes.map(\.id)), Set(b.nodes.map(\.id)))
    }
}
