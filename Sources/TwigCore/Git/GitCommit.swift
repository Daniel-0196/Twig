import Foundation

public struct GitCommit: Equatable {
    public var hash: String
    public var date: Date
    public var subject: String

    public init(hash: String, date: Date, subject: String) {
        self.hash = hash
        self.date = date
        self.subject = subject
    }
}

public enum GitLogParser {
    /// 解析 `git log --pretty=format:%h%x09%aI%x09%s` 的输出
    public static func parse(_ output: String) -> [GitCommit] {
        let formatter = ISO8601DateFormatter()
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3, let date = formatter.date(from: String(parts[1])) else { return nil }
            return GitCommit(hash: String(parts[0]), date: date, subject: String(parts[2]))
        }
    }
}
