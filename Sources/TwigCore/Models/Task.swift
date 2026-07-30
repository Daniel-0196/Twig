import Foundation
import SwiftData

@Model
public final class Task {
    public var title: String
    public var isDone: Bool = false
    public var estimateMin: Int?
    public var dueDate: Date?
    public var completedAt: Date?
    public var sortOrder: Double = 0
    public var goal: Goal?
    @Relationship(deleteRule: .nullify, inverse: \TimeEntry.task)
    public var timeEntries: [TimeEntry] = []

    public init(title: String, estimateMin: Int? = nil, dueDate: Date? = nil, sortOrder: Double = 0) {
        self.title = title
        self.estimateMin = estimateMin
        self.dueDate = dueDate
        self.sortOrder = sortOrder
    }
}
