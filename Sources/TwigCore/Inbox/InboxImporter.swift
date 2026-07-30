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
        guard let data = FileManager.default.contents(atPath: inboxURL.path),
              let text = String(data: data, encoding: .utf8)
        else { return ImportReport() }

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

        // 清空收件箱
        try "".write(to: inboxURL, atomically: true, encoding: .utf8)

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
