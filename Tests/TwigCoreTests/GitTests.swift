import XCTest
@testable import TwigCore

final class GitTests: XCTestCase {
    func testParseLogOutput() {
        let output = "a1b2c3d\t2026-07-29T10:00:00+08:00\tfeat: 修 shader\n9z8y7x6\t2026-07-28T09:30:00+08:00\tchore: 清理"
        let commits = GitLogParser.parse(output)
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].hash, "a1b2c3d")
        XCTAssertEqual(commits[0].subject, "feat: 修 shader")
        XCTAssertLessThan(commits[1].date, commits[0].date)
        XCTAssertEqual(GitLogParser.parse(""), [])
        XCTAssertEqual(GitLogParser.parse("乱写的行"), [])
    }

    func testReaderReadsRealRepo() throws {
        // 建一个带两条提交的真实临时仓库
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func shell(_ cmd: String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "cd '\(dir.path)' && \(cmd)"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        shell("git init -q && git config user.email t@t && git config user.name t")
        shell("echo a > a.txt && git add . && GIT_AUTHOR_DATE='2026-07-29T10:00:00' GIT_COMMITTER_DATE='2026-07-29T10:00:00' git commit -qm '第一条提交'")
        shell("echo b >> a.txt && git add . && git commit -qm '第二条提交'")

        let reader = GitReader()
        let branch = try reader.currentBranch(repoPath: dir.path)
        XCTAssertFalse(branch.isEmpty)
        let commits = try reader.log(repoPath: dir.path, since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits.first?.subject, "第二条提交")   // 新提交在前
    }

    func testReaderRejectsNonRepo() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("twig-nogit-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try GitReader().log(repoPath: dir.path, since: Date())) { error in
            XCTAssertEqual(error as? GitError, .notARepo)
        }
    }
}
