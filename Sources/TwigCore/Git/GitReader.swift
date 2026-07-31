import Foundation

public enum GitError: Error, Equatable {
    case notARepo
    case timedOut
    case failed(Int32)
}

public struct GitReader {
    private let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    public func currentBranch(repoPath: String) throws -> String {
        let (code, out) = try run(["-C", repoPath, "rev-parse", "--abbrev-ref", "HEAD"], timeout: 5)
        guard code == 0 else { throw GitError.notARepo }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func log(repoPath: String, since: Date, timeout: TimeInterval = 5) throws -> [GitCommit] {
        let iso = ISO8601DateFormatter().string(from: since)
        let (code, out) = try run([
            "-C", repoPath, "log",
            "--since=\(iso)", "--max-count=500",
            "--pretty=format:%h%x09%aI%x09%s",
        ], timeout: timeout)
        guard code == 0 else { throw code == 128 ? GitError.notARepo : GitError.failed(code) }
        return GitLogParser.parse(out)
    }

    private func run(_ args: [String], timeout: TimeInterval) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw GitError.timedOut
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
