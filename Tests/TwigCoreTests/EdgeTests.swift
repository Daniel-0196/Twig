import XCTest
import SwiftData
@testable import TwigCore

final class EdgeTests: XCTestCase {
    @MainActor
    func testEdgePersistsBetweenGoals() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let p = Project(name: "twig", colorHint: "#D97757")
        ctx.insert(p)
        let a = Goal(title: "v0.2", horizon: .short, targetDate: nil)
        let b = Goal(title: "v0.5", horizon: .mid, targetDate: nil)
        a.project = p; b.project = p
        ctx.insert(a); ctx.insert(b)
        let e = Edge(type: .sequence, from: a, to: b)
        ctx.insert(e)
        try ctx.save()

        let edges = try ctx.fetch(FetchDescriptor<Edge>())
        XCTAssertEqual(edges.count, 1)
        XCTAssertEqual(edges[0].from?.title, "v0.2")
        XCTAssertEqual(edges[0].to?.title, "v0.5")
        XCTAssertEqual(a.outEdges.count, 1)
        XCTAssertEqual(b.inEdges.count, 1)
    }

    @MainActor
    func testGoalNewFieldsDefaults() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let g = Goal(title: "g", horizon: .short, targetDate: nil)
        container.mainContext.insert(g)
        XCTAssertFalse(g.revealed)
        XCTAssertNil(g.customX)
        XCTAssertNil(g.customY)
    }

    @MainActor
    func testCascadeDeleteGoalRemovesEdges() throws {
        let container = try TwigStore.makeContainer(inMemory: true)
        let ctx = container.mainContext
        let a = Goal(title: "a", horizon: .short, targetDate: nil)
        let b = Goal(title: "b", horizon: .mid, targetDate: nil)
        ctx.insert(a); ctx.insert(b)
        ctx.insert(Edge(type: .sequence, from: a, to: b))
        try ctx.save()
        ctx.delete(a)
        try ctx.save()
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Edge>()), 0)
    }
}
