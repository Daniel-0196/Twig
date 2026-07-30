import Foundation
import SwiftData

@Model
public final class Project {
    public var name: String
    public var colorHint: String   // "#D97757" 形式，枝干/节点继承此色
    public var repoPath: String?
    public var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Goal.project)
    public var goals: [Goal] = []

    public init(name: String, colorHint: String, repoPath: String? = nil, createdAt: Date = .now) {
        self.name = name
        self.colorHint = colorHint
        self.repoPath = repoPath
        self.createdAt = createdAt
    }
}
