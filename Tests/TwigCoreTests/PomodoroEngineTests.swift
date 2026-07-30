import XCTest
@testable import TwigCore

final class PomodoroEngineTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private func makeEngine(config: TimerConfig = TimerConfig()) -> PomodoroEngine {
        PomodoroEngine(config: config, now: { [unowned self] in self.now })
    }

    func testPomodoroCompletesAfter25MinAndStartsShortBreak() {
        let engine = makeEngine()
        engine.startFocus(mode: .pomodoro)
        now = now.addingTimeInterval(24 * 60)
        XCTAssertNil(engine.tick())
        now = now.addingTimeInterval(60)
        let event = engine.tick()
        guard case .focusCompleted(let duration) = event else {
            return XCTFail("期望 focusCompleted，得到 \(String(describing: event))")
        }
        XCTAssertEqual(duration, 25 * 60, accuracy: 1)
        guard case .onBreak(_, _, let isLong) = engine.state else {
            return XCTFail("期望进入短休息")
        }
        XCTAssertFalse(isLong)
    }

    func testFourthPomodoroTriggersLongBreak() {
        let engine = makeEngine()
        for i in 1...4 {
            engine.startFocus(mode: .pomodoro)
            now = now.addingTimeInterval(25 * 60)
            _ = engine.tick()
            if i < 4 {
                now = now.addingTimeInterval(5 * 60)
                XCTAssertEqual(engine.tick(), .breakCompleted)
            }
        }
        guard case .onBreak(_, let endsAt, let isLong) = engine.state else {
            return XCTFail("第 4 个番茄后应进入休息")
        }
        XCTAssertTrue(isLong)
        // 注意：相对注入的假时钟断言（brief 原文用 timeIntervalSinceNow，假时钟为 1970 年，永远失败）
        XCTAssertEqual(endsAt.timeIntervalSince(now), 15 * 60, accuracy: 60)
    }

    func testStopwatchNeverAutoCompletes() {
        let engine = makeEngine()
        engine.startFocus(mode: .stopwatch)
        now = now.addingTimeInterval(3 * 3600)
        XCTAssertNil(engine.tick())
        guard case .stopped(let recorded) = engine.stop(discard: false) else {
            return XCTFail("stop 应返回 stopped")
        }
        XCTAssertEqual(recorded ?? 0, 3 * 3600, accuracy: 1)
        XCTAssertEqual(engine.state, .idle)
    }

    func testCustomCountdown() {
        let engine = makeEngine()
        engine.startFocus(mode: .countdown(minutes: 40))
        now = now.addingTimeInterval(40 * 60)
        XCTAssertNotNil(engine.tick())
    }

    func testStopDiscardRecordsNothing() {
        let engine = makeEngine()
        engine.startFocus(mode: .pomodoro)
        now = now.addingTimeInterval(600)
        XCTAssertEqual(engine.stop(discard: true), .stopped(recorded: nil))
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.completedPomodoros, 0)
    }

    func testAutoStartBreakOffLeavesIdle() {
        var config = TimerConfig()
        config.autoStartBreak = false
        let engine = makeEngine(config: config)
        engine.startFocus(mode: .pomodoro)
        now = now.addingTimeInterval(25 * 60)
        _ = engine.tick()
        XCTAssertEqual(engine.state, .idle)
    }
}
