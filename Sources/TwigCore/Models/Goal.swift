import Foundation
import SwiftData

public enum Horizon: String, Codable, CaseIterable {
    case short, mid, long
}

@Model
public final class Goal {
    public var title: String
    public var horizon: Horizon
    public var targetDate: Date?   // 长期只定季度时存季度末日期，UI 显示「Q4」
    public var isDone: Bool = false
    public var sortOrder: Double = 0
    public var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \Task.goal)
    public var tasks: [Task] = []

    public init(title: String, horizon: Horizon, targetDate: Date?, sortOrder: Double = 0) {
        self.title = title
        self.horizon = horizon
        self.targetDate = targetDate
        self.sortOrder = sortOrder
    }
}
