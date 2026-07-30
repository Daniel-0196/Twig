import XCTest
@testable import TwigCore

final class StoreBackupTests: XCTestCase {
    func testBackupCopiesStoreFilesAndPrunesOld() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("twig-backup-\(UUID().uuidString)")
        let support = root.appendingPathComponent("support")
        let backups = root.appendingPathComponent("backups")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let store = support.appendingPathComponent("twig.store")
        try "db".write(to: store, atomically: true, encoding: .utf8)
        try "wal".write(to: support.appendingPathComponent("twig.store-wal"), atomically: true, encoding: .utf8)

        for _ in 0..<5 {
            try StoreBackup.backupNow(storeURL: store, backupsDir: backups, keep: 3, supportDir: support)
            Thread.sleep(forTimeInterval: 1.1)   // 时间戳精确到秒，错开
        }
        let dirs = try fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        XCTAssertEqual(dirs.count, 3)   // 只留最近 3 份
        let newest = dirs.sorted { $0.lastPathComponent < $1.lastPathComponent }.last!
        let files = try fm.contentsOfDirectory(at: newest, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertTrue(files.contains("twig.store"))
        XCTAssertTrue(files.contains("twig.store-wal"))
    }

    func testBackupWithoutStoreIsNoOp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try StoreBackup.backupNow(
            storeURL: root.appendingPathComponent("不存在.store"),
            backupsDir: root.appendingPathComponent("backups"),
            supportDir: root))
    }
}
