import XCTest
@testable import TwigCore

final class CrashRecoveryTests: XCTestCase {
    func testFindsOnlyUnclosedEntries() {
        let closed = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 100))
        closed.endedAt = Date(timeIntervalSince1970: 200)
        let open = TimeEntry(kind: .stopwatch, startedAt: Date(timeIntervalSince1970: 300))
        let result = CrashRecovery.openEntries([closed, open])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].startedAt, Date(timeIntervalSince1970: 300))
    }

    func testCloseUsesLastHeartbeat() {
        let entry = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 1000))
        entry.lastHeartbeat = Date(timeIntervalSince1970: 1300)   // 计到 1300 就崩了
        CrashRecovery.close(entry, fallback: Date(timeIntervalSince1970: 9999))
        XCTAssertEqual(entry.endedAt, Date(timeIntervalSince1970: 1300))
    }

    func testCloseNeverEndsBeforeStart() {
        let entry = TimeEntry(kind: .pomodoro, startedAt: Date(timeIntervalSince1970: 1000))
        entry.lastHeartbeat = Date(timeIntervalSince1970: 900)   // 异常数据：心跳早于开始
        CrashRecovery.close(entry, fallback: Date(timeIntervalSince1970: 800))
        XCTAssertEqual(entry.endedAt, entry.startedAt)
    }
}
