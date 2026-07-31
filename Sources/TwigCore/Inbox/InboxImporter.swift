import Foundation

public struct ImportReport: Equatable {
    public var imported: Int = 0
    public var skippedDuplicates: Int = 0
    public var badLines: [String] = []
}

@MainActor
public final class InboxImporter {
    private let store: TaskStore

    public init(store: TaskStore) {
        self.store = store
    }

    @discardableResult
    public func importInbox(at inboxURL: URL, badLinesURL: URL) throws -> ImportReport {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inboxURL.path) else { return ImportReport() }

        // 先把收件箱原子 rename 成 processing 文件再处理：
        // read→清空之间 CLI 追加的行会落在重建的新 inbox 里，不会被误清（丢数据窗口）
        let processingURL = inboxURL.deletingPathExtension()
            .appendingPathExtension("processing.jsonl")
        try? fm.removeItem(at: processingURL)   // 上次崩溃残留
        let renamed: Bool
        do {
            try fm.moveItem(at: inboxURL, to: processingURL)
            renamed = true
        } catch {
            renamed = false   // rename 失败兜底：直接读原文件，处理后 truncate
        }
        let sourceURL = renamed ? processingURL : inboxURL
        guard let data = fm.contents(atPath: sourceURL.path),
              let text = String(data: data, encoding: .utf8)
        else {
            if renamed { try? fm.removeItem(at: processingURL) }
            return ImportReport()
        }

        var report = ImportReport()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let item = InboxParser.parse(line: line) else {
                report.badLines.append(line)
                continue
            }
            if store.taskExists(title: item.title, projectName: item.project) {
                report.skippedDuplicates += 1
                continue
            }
            let project = store.findOrCreateProject(named: item.project)
            let goal = store.findOrCreateGoal(in: project, title: item.goal ?? "收集箱")
            store.addTask(to: goal, title: item.title, estimateMin: item.estimateMin, dueDate: item.due)
            report.imported += 1
        }

        if renamed {
            // processing 文件处理完直接删除；inbox 由 watcher/CLI 按需重建
            try? fm.removeItem(at: processingURL)
        } else {
            // 兜底清空：truncate 保持 inode（atomic write 会替换 inode，文件监视器永久失效）
            let handle = try FileHandle(forWritingTo: inboxURL)
            try handle.truncate(atOffset: 0)
            try handle.close()
        }

        // 坏行留档（追加，不覆盖）
        if !report.badLines.isEmpty {
            let archive = report.badLines.joined(separator: "\n") + "\n"
            if FileManager.default.fileExists(atPath: badLinesURL.path),
               let handle = try? FileHandle(forWritingTo: badLinesURL) {
                handle.seekToEndOfFile()
                handle.write(Data(archive.utf8))
                try? handle.close()
            } else {
                try? archive.write(to: badLinesURL, atomically: true, encoding: .utf8)
            }
        }
        return report
    }
}
