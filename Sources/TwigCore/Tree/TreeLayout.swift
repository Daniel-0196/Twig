import CoreGraphics
import Foundation
import SwiftData

public enum PullDirection: String, Codable, CaseIterable {
    case up, down, left, right
}

/// 方向几何：unit = 拖拽方向单位向量；chainSign = 链条朝土壤的符号（沿主轴）
public struct DirGeom {
    public var axisIsX: Bool
    public var unit: CGPoint
    public var soil: CGFloat
    public var chainSign: CGFloat
    public var buriedSign: CGFloat

    public init(axisIsX: Bool, unit: CGPoint, soil: CGFloat, chainSign: CGFloat, buriedSign: CGFloat) {
        self.axisIsX = axisIsX
        self.unit = unit
        self.soil = soil
        self.chainSign = chainSign
        self.buriedSign = buriedSign
    }
}

public enum TreeGeom {
    public static func geom(for direction: PullDirection, rect: CGRect) -> DirGeom {
        switch direction {
        case .up:
            return DirGeom(axisIsX: false, unit: CGPoint(x: 0, y: -1),
                           soil: rect.maxY, chainSign: 1, buriedSign: 1)
        case .down:
            return DirGeom(axisIsX: false, unit: CGPoint(x: 0, y: 1),
                           soil: rect.minY, chainSign: -1, buriedSign: -1)
        case .left:
            return DirGeom(axisIsX: true, unit: CGPoint(x: -1, y: 0),
                           soil: rect.minX, chainSign: -1, buriedSign: -1)
        case .right:
            return DirGeom(axisIsX: true, unit: CGPoint(x: 1, y: 0),
                           soil: rect.maxX, chainSign: 1, buriedSign: 1)
        }
    }
}

public struct Placement: Equatable {
    public var goal: PersistentIdentifier
    public var center: CGPoint
    public var isBuried: Bool

    public init(goal: PersistentIdentifier, center: CGPoint, isBuried: Bool) {
        self.goal = goal
        self.center = center
        self.isBuried = isBuried
    }
}

public enum TreeLayout {
    public static let mainGap: CGFloat = 190
    public static let siblingGap: CGFloat = 110
    public static let rootInset: CGFloat = 90
    public static let depthExtra: CGFloat = 50
    public static let buriedBase: CGFloat = 120
    public static let buriedStep: CGFloat = 100

    // 确定性抖动（按 goal id 哈希）
    private static func hash01(_ id: PersistentIdentifier) -> Double {
        var h: UInt64 = 5381
        // 本 SDK 的 PersistentIdentifier 无 uriRepresentation；沿用 BranchLayout.stableID 的
        // String(describing:) 方案（已入库跨进程稳定；未入库如单测进程内稳定）
        for b in String(describing: id).utf8 {
            h = ((h &<< 5) &+ h) &+ UInt64(b)
        }
        return Double(h % 65536) / 65536.0
    }
    private static func jitter(_ g: Goal) -> CGFloat { CGFloat(hash01(g.persistentModelID) - 0.5) * 44 }
    private static func spacing(_ g: Goal) -> CGFloat { CGFloat(0.88 + hash01(g.persistentModelID) * 0.24) }

    /// 只自动排未手动摆放（customX/Y 为 nil）的节点；手动节点按 custom 位置原样写入；返回 goal id → 中心点
    public static func place(goals: [Goal], edges: [Edge], rect: CGRect,
                             direction: PullDirection) -> [PersistentIdentifier: CGPoint] {
        var result: [PersistentIdentifier: CGPoint] = [:]
        let depth = TreeTopology.depths(goals: goals, edges: edges)
        // frontier 遍历只认入参节点集：边可能指向集合外的节点（如画板过滤掉的"收集箱"），
        // 不拦住的话布局会把集合外节点当隐形节点排进来
        let memberIDs = Set(goals.map(\.persistentModelID))

        // 项目分组（保持 projects 传入顺序用 Goal.project）
        var byProject: [PersistentIdentifier: (project: Project, goals: [Goal])] = [:]
        var order: [PersistentIdentifier] = []
        for g in goals {
            guard let p = g.project else { continue }
            if byProject[p.persistentModelID] == nil {
                byProject[p.persistentModelID] = (p, [])
                order.append(p.persistentModelID)
            }
            byProject[p.persistentModelID]!.goals.append(g)
        }

        for (pi, pid) in order.enumerated() {
            let group = byProject[pid]!
            // 左侧内边距 120：节点卡以中心点 ±75（加抖动 ±22）近似半宽，<97 会被画布左缘裁切
            let baseCross: CGFloat = (direction == .up || direction == .down)
                ? rect.minX + 120 + CGFloat(pi) * 260
                : rect.minY + 50 + CGFloat(pi) * 150

            // 手动摆放的节点：不参与自动布局，按 custom 位置原样写入。
            // 仅限已出土节点——埋土节点属于土壤（土线外的槽位），若沿用 custom 位置，
            // 埋土剪影会钉在画布内、茎线断在半空而节点本身在白底上近不可见
            for g in group.goals where g.revealed {
                if let cx = g.customX {
                    result[g.persistentModelID] = CGPoint(x: cx, y: g.customY ?? 0)
                }
            }

            let shown = group.goals.filter { $0.revealed && $0.customX == nil }
            let hidden = group.goals.filter { !$0.revealed }
                .sorted { (depth[$0.persistentModelID] ?? 0) < (depth[$1.persistentModelID] ?? 0) }

            // 根随出土深度迁移
            let dMax = CGFloat(shown.map { max(0, depth[$0.persistentModelID] ?? 0) }.max() ?? 0)
            let inset = max(rootInset, dMax * mainGap + depthExtra)
            let rootBase: CGFloat
            switch direction {
            case .up:    rootBase = rect.maxY - inset
            case .down:  rootBase = rect.minY + inset
            case .left:  rootBase = rect.minX + inset
            case .right: rootBase = rect.maxX - inset
            }
            let chainSign: CGFloat = (direction == .up || direction == .right) ? 1 : -1
            let buriedSign = chainSign
            let soil: CGFloat = (direction == .up) ? rect.maxY : (direction == .down) ? rect.minY
                              : (direction == .left) ? rect.minX : rect.maxX

            func setAbs(_ g: Goal, main: CGFloat, cross: CGFloat) {
                let pt = (direction == .up || direction == .down)
                    ? CGPoint(x: cross, y: main)
                    : CGPoint(x: main, y: cross)
                result[g.persistentModelID] = pt
            }

            // 根层
            let roots = shown.filter { (depth[$0.persistentModelID] ?? -1) <= 0 }
            for (i, n) in roots.enumerated() {
                let cross = baseCross + (CGFloat(i) - CGFloat(roots.count - 1) / 2) * siblingGap + jitter(n)
                setAbs(n, main: rootBase, cross: cross)
            }

            // 逐层扇开
            var frontier = roots
            var dk: CGFloat = 1
            while !frontier.isEmpty && dk < 20 {
                var next: [Goal] = []
                for parent in frontier {
                    let kids = TreeTopology.outgoing(from: parent, edges: edges)
                        .compactMap { $0.to }
                        .filter { $0.revealed && $0.customX == nil && memberIDs.contains($0.persistentModelID) }
                    let parentCross = result[parent.persistentModelID]!.xOrY(cross: direction)
                    for (i, kid) in kids.enumerated() {
                        let cross = parentCross + (CGFloat(i) - CGFloat(kids.count - 1) / 2) * siblingGap + jitter(kid)
                        setAbs(kid, main: rootBase + chainSign * dk * mainGap * spacing(kid), cross: cross)
                        next.append(kid)
                    }
                }
                frontier = next
                dk += 1
            }

            // 孤立已揭示节点：排在根层旁边
            let orphans = shown.filter { n in
                !roots.contains(where: { $0.persistentModelID == n.persistentModelID })
                    && result[n.persistentModelID] == nil
            }
            for (i, n) in orphans.enumerated() {
                setAbs(n, main: rootBase, cross: baseCross + 170 + CGFloat(i) * 100 + jitter(n))
            }

            // 埋土：按深度排，土线外
            for (j, n) in hidden.enumerated() {
                setAbs(n, main: soil + buriedSign * (buriedBase + CGFloat(j) * buriedStep),
                       cross: baseCross + jitter(n))
            }
        }
        return result
    }
}

private extension CGPoint {
    func xOrY(cross direction: PullDirection) -> CGFloat {
        (direction == .up || direction == .down) ? x : y
    }
}
