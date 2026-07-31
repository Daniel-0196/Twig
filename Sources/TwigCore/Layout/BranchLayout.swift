import CoreGraphics
import Foundation
import SwiftData

public enum BranchDirection: String, Codable, CaseIterable {
    case right, left, up, down

    /// 纵向（up/down）时横条组装为上下结构，收起态需要更高
    public var isVertical: Bool { self == .up || self == .down }
}

public struct BranchTuning: Equatable {
    public var direction: BranchDirection = .right
    public var curveTension: CGFloat = 0.35
    public var branchSpacing: CGFloat = 150
    public var nodeSpacing: CGFloat = 64
    public var fadeDistance: CGFloat = 320
    public var dragExpandThreshold: CGFloat = 24
    public init() {}
}

public struct BranchNode: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let colorHex: String
    public var center: CGPoint
    public var opacity: Double
    public var dashed: Bool

    public init(id: UUID, title: String, subtitle: String, colorHex: String,
                center: CGPoint, opacity: Double, dashed: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.colorHex = colorHex
        self.center = center
        self.opacity = opacity
        self.dashed = dashed
    }
}

public struct BranchEdge: Equatable {
    public var from: CGPoint
    public var to: CGPoint
    public var c1: CGPoint
    public var c2: CGPoint
    public var colorHex: String
    public var dashed: Bool
    public var faded: Bool

    public init(from: CGPoint, to: CGPoint, c1: CGPoint, c2: CGPoint,
                colorHex: String, dashed: Bool, faded: Bool) {
        self.from = from
        self.to = to
        self.c1 = c1
        self.c2 = c2
        self.colorHex = colorHex
        self.dashed = dashed
        self.faded = faded
    }
}

public struct BranchLayoutResult: Equatable {
    public var nodes: [BranchNode]
    public var edges: [BranchEdge]
    public var contentSize: CGSize
    public var direction: BranchDirection
    /// 归一化后的锚点（枝干起点）。布局输出整体做了 min-corner 平移，
    /// 锚点不再是传入值，所有"相对锚点"的判断都要用它。
    public var anchor: CGPoint

    public init(nodes: [BranchNode], edges: [BranchEdge], contentSize: CGSize,
                direction: BranchDirection, anchor: CGPoint) {
        self.nodes = nodes
        self.edges = edges
        self.contentSize = contentSize
        self.direction = direction
        self.anchor = anchor
    }
}

public enum BranchLayout {
    public static func compute(projects: [Project], anchor: CGPoint,
                               tuning: BranchTuning = .init(), now: Date = .now) -> BranchLayoutResult {
        var nodes: [BranchNode] = []
        var edges: [BranchEdge] = []
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "M/d"

        // 主轴单位向量（枝干延展方向）与交叉轴单位向量（节点错开方向）
        let main: CGPoint
        switch tuning.direction {
        case .right: main = CGPoint(x: 1, y: 0)
        case .left:  main = CGPoint(x: -1, y: 0)
        case .down:  main = CGPoint(x: 0, y: 1)
        case .up:    main = CGPoint(x: 0, y: -1)
        }
        let cross = CGPoint(x: -main.y, y: main.x)   // 主轴逆时针旋转 90°

        func layoutPoint(main m: CGFloat, cross c: CGFloat) -> CGPoint {
            CGPoint(x: anchor.x + main.x * m + cross.x * c,
                    y: anchor.y + main.y * m + cross.y * c)
        }

        for (projectIndex, project) in projects.enumerated() {
            let goals = project.goals
                .filter { !$0.isDone }
                .sorted { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }
            guard !goals.isEmpty else { continue }
            let mainOffset = tuning.branchSpacing * CGFloat(projectIndex + 1)
            var previousPoint = anchor

            for (goalIndex, goal) in goals.enumerated() {
                // 交叉轴正方向错开：日期近的离 anchor 近
                let center = layoutPoint(main: mainOffset,
                                         cross: 48 + CGFloat(goalIndex) * tuning.nodeSpacing)
                let opacity = max(0.3, 1 - mainOffset / tuning.fadeDistance)
                let dashed = goal.horizon != .short
                let subtitle = goal.targetDate.map { dayFmt.string(from: $0) } ?? "未定"
                nodes.append(BranchNode(
                    id: stableID(for: goal),
                    title: goal.title,
                    subtitle: subtitle,
                    colorHex: project.colorHint,
                    center: center,
                    opacity: opacity,
                    dashed: dashed
                ))
                let d = mainOffset * tuning.curveTension
                edges.append(BranchEdge(
                    from: previousPoint,
                    to: center,
                    c1: CGPoint(x: previousPoint.x + main.x * d, y: previousPoint.y + main.y * d),
                    c2: CGPoint(x: center.x - main.x * d, y: center.y - main.y * d),
                    colorHex: project.colorHint,
                    dashed: dashed && goalIndex == goals.count - 1,
                    faded: opacity < 0.7
                ))
                previousPoint = center
            }
        }

        // contentSize/坐标归一化：按锚点+节点+边控制点的实际包围盒做 min-corner 平移。
        // .left/.up 主轴伸向负方向、.down 交叉轴伸向 x 负方向，不平移节点会渲到窗口外；
        // 统一在这里归一化，保证四方向所有节点中心都落在 [0, contentSize] 内。
        let pad: CGFloat = 48
        var minX = anchor.x, minY = anchor.y, maxX = anchor.x, maxY = anchor.y
        func absorb(_ p: CGPoint) {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        for node in nodes { absorb(node.center) }
        for edge in edges {
            absorb(edge.from); absorb(edge.to)
            absorb(edge.c1); absorb(edge.c2)
        }
        let tx = pad - minX, ty = pad - minY
        for i in nodes.indices {
            nodes[i].center = CGPoint(x: nodes[i].center.x + tx, y: nodes[i].center.y + ty)
        }
        for i in edges.indices {
            edges[i].from = CGPoint(x: edges[i].from.x + tx, y: edges[i].from.y + ty)
            edges[i].to = CGPoint(x: edges[i].to.x + tx, y: edges[i].to.y + ty)
            edges[i].c1 = CGPoint(x: edges[i].c1.x + tx, y: edges[i].c1.y + ty)
            edges[i].c2 = CGPoint(x: edges[i].c2.x + tx, y: edges[i].c2.y + ty)
        }
        let size = CGSize(width: maxX - minX + pad * 2, height: maxY - minY + pad * 2)
        return BranchLayoutResult(nodes: nodes, edges: edges, contentSize: size,
                                  direction: tuning.direction,
                                  anchor: CGPoint(x: anchor.x + tx, y: anchor.y + ty))
    }

    /// 同一 goal 多次布局要拿到同一个 id，否则 SwiftUI 动画会跳。
    /// 已入库的 goal 用 persistentModelID；未入库（纯内存，如单元测试）退化为对象标识。
    /// 公开出来是为了让 AppState.moveGoal 能用 nodeID 找回 goal。
    public static func stableID(for goal: Goal) -> UUID {
        let key: String
        if goal.modelContext != nil {
            key = String(describing: goal.persistentModelID)
        } else {
            key = "detached-\(ObjectIdentifier(goal).hashValue)"
        }
        // FNV-1a 散列两遍，铺成 16 字节 UUID
        var bytes = [UInt8](repeating: 0, count: 16)
        for round in 0..<2 {
            var hash: UInt64 = 1469598103934665603 &+ UInt64(round)
            for byte in key.utf8 {
                hash = (hash ^ UInt64(byte)) &* 1099511628211
            }
            for i in 0..<8 {
                bytes[round * 8 + i] = UInt8(truncatingIfNeeded: hash >> (i * 8))
            }
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
