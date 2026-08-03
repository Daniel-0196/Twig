import XCTest
import CoreGraphics
@testable import TwigCore

final class PullPhysicsTests: XCTestCase {
    func testFollowIntegrationApproachesTarget() {
        var s = PullSession()
        s.targetOffset = CGSize(width: 0, height: -260)   // 向上拽
        for _ in 0..<30 { PullPhysics.step(&s, direction: .up) }
        XCTAssertLessThan(s.offset.height, -150)   // 趋近目标（被重力吃掉一部分）
        XCTAssertLessThan(s.velocity.height, 0)
    }

    func testGravityPullsBackWhenTargetZero() {
        var s = PullSession()
        s.offset = CGSize(width: 0, height: -200)
        s.targetOffset = .zero   // 松手的目标
        for _ in 0..<200 { PullPhysics.step(&s, direction: .up) }
        XCTAssertEqual(s.offset.height, 0, accuracy: 1)   // 被吸回土里
    }

    func testPeakPullSurvivesGravityFallback() {
        var s = PullSession()
        s.targetOffset = CGSize(width: 0, height: -260)
        for _ in 0..<10 { PullPhysics.step(&s, direction: .up) }
        let peak = s.peakRaw
        XCTAssertGreaterThan(peak, 100)
        // 回拉（手往回松），峰值保留
        s.targetOffset = CGSize(width: 0, height: -60)
        for _ in 0..<10 { PullPhysics.step(&s, direction: .up) }
        XCTAssertEqual(s.peakRaw, peak)
        XCTAssertEqual(PullPhysics.pullMain(s, direction: .up), peak)
    }

    func testRevealConsumesPull() {
        var s = PullSession()
        s.peakRaw = 300
        XCTAssertTrue(PullPhysics.checkReveal(&s, direction: .up, buriedDepth: 140))
        XCTAssertEqual(s.consumed, 140)
        // 消耗后同一波拔力不够第二个（埋深 240）
        XCTAssertFalse(PullPhysics.checkReveal(&s, direction: .up, buriedDepth: 240))
        // 继续用力到峰值 300+140 → 第二个出土
        s.peakRaw = 450
        XCTAssertTrue(PullPhysics.checkReveal(&s, direction: .up, buriedDepth: 240))
    }

    func testSpringEaseOvershoots() {
        XCTAssertEqual(PullPhysics.springEase(0), 0, accuracy: 0.001)
        XCTAssertEqual(PullPhysics.springEase(1), 1, accuracy: 0.001)
        // easeOutBack 中途过冲
        XCTAssertGreaterThan(PullPhysics.springEase(0.8), 1.0)
    }

    func testDirectionSigns() {
        // 向上拔：offset.y 为负，pullMain 为正
        var s = PullSession()
        s.peakRaw = 100
        s.offset = CGSize(width: 0, height: -100)
        XCTAssertEqual(PullPhysics.pullMain(s, direction: .up), 100)
        // 向下拔：offset.y 为正
        s.offset = CGSize(width: 0, height: 100)
        s.peakRaw = 0
        XCTAssertEqual(PullPhysics.pullMain(s, direction: .down), 100)
    }
}
