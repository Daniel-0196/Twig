import Foundation

public struct InboxItem: Codable, Equatable {
    public var id: UUID
    public var title: String
    public var project: String
    public var goal: String?
    public var goalHorizon: String?   // "short"/"mid"/"long"，仅新建 goal 时生效
    public var due: Date?
    public var estimateMin: Int?
    public var source: String      // "claude" / "codex" / "cli"
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, project: String, goal: String? = nil,
                goalHorizon: String? = nil, due: Date? = nil, estimateMin: Int? = nil,
                source: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.project = project
        self.goal = goal
        self.goalHorizon = goalHorizon
        self.due = due
        self.estimateMin = estimateMin
        self.source = source
        self.createdAt = createdAt
    }
}

public enum InboxParser {
    public static func parse(line: String) -> InboxItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InboxItem.self, from: data)
    }

    public static func encode(_ item: InboxItem) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        return String(data: data, encoding: .utf8)!
    }
}
