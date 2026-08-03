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

    // 拔树画板状态
    public var revealed: Bool = false       // 是否已出土（短期目标初始化时置 true，见 Task 5）
    public var customX: Double? = nil       // 手动摆放位置（覆盖自动布局）
    public var customY: Double? = nil
    @Relationship(deleteRule: .cascade, inverse: \Edge.from)
    public var outEdges: [Edge] = []
    @Relationship(deleteRule: .cascade, inverse: \Edge.to)
    public var inEdges: [Edge] = []

    public init(title: String, horizon: Horizon, targetDate: Date?, sortOrder: Double = 0) {
        self.title = title
        self.horizon = horizon
        self.targetDate = targetDate
        self.sortOrder = sortOrder
    }
}
