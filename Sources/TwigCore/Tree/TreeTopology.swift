import Foundation
import SwiftData

public enum TreeTopology {
    private static func seqEdges(_ edges: [Edge]) -> [Edge] {
        edges.filter { $0.type == .sequence }
    }

    /// seq 入度 0 = 根（depth 0），沿出边递增；孤立/不可达 = -1
    public static func depths(goals: [Goal], edges: [Edge]) -> [PersistentIdentifier: Int] {
        let seq = seqEdges(edges)
        var indeg: [PersistentIdentifier: Int] = [:]
        for g in goals { indeg[g.persistentModelID] = 0 }
        var touched: Set<PersistentIdentifier> = []
        for e in seq {
            if let from = e.from { touched.insert(from.persistentModelID) }
            if let to = e.to {
                indeg[to.persistentModelID, default: 0] += 1
                touched.insert(to.persistentModelID)
            }
        }
        var depth: [PersistentIdentifier: Int] = [:]
        var queue = goals.filter { indeg[$0.persistentModelID] == 0 && touched.contains($0.persistentModelID) }
        queue.forEach { depth[$0.persistentModelID] = 0 }
        var guardCount = 0
        while !queue.isEmpty && guardCount < 500 {
            guardCount += 1
            let cur = queue.removeFirst()
            let curDepth = depth[cur.persistentModelID] ?? 0
            for e in seq where e.from?.persistentModelID == cur.persistentModelID {
                guard let nxt = e.to else { continue }
                let id = nxt.persistentModelID
                if depth[id] == nil || depth[id]! < curDepth + 1 {
                    depth[id] = curDepth + 1
                    queue.append(nxt)
                }
            }
        }
        for g in goals where depth[g.persistentModelID] == nil {
            depth[g.persistentModelID] = -1
        }
        return depth
    }

    public static func isRoot(_ goal: Goal, edges: [Edge]) -> Bool {
        !seqEdges(edges).contains { $0.to?.persistentModelID == goal.persistentModelID }
    }

    /// 沿 seq 双向 BFS：拔树的单位（一棵"树"）
    public static func component(of goal: Goal, edges: [Edge]) -> (ids: Set<PersistentIdentifier>, depths: [PersistentIdentifier: Int]) {
        let seq = seqEdges(edges)
        var ids: Set<PersistentIdentifier> = [goal.persistentModelID]
        var depths: [PersistentIdentifier: Int] = [goal.persistentModelID: 0]
        var queue = [goal]
        while !queue.isEmpty {
            let cur = queue.removeFirst()
            let d = depths[cur.persistentModelID] ?? 0
            for e in seq {
                let other: Goal?
                if e.from?.persistentModelID == cur.persistentModelID { other = e.to }
                else if e.to?.persistentModelID == cur.persistentModelID { other = e.from }
                else { continue }
                guard let o = other, !ids.contains(o.persistentModelID) else { continue }
                ids.insert(o.persistentModelID)
                depths[o.persistentModelID] = d + 1
                queue.append(o)
            }
        }
        return (ids, depths)
    }

    /// 子节点出土 ⇒ 其 seq 祖先必须先出土（迭代到不动点）
    public static func sanitizeReveal(goals: [Goal], edges: [Edge]) {
        let seq = seqEdges(edges)
        var changed = true
        var guardCount = 0
        while changed && guardCount < 20 {
            guardCount += 1
            changed = false
            for e in seq {
                guard let a = e.from, let b = e.to else { continue }
                if b.revealed && !a.revealed { a.revealed = true; changed = true }
            }
        }
    }

    public static func outgoing(from: Goal, edges: [Edge]) -> [Edge] {
        seqEdges(edges).filter { $0.from?.persistentModelID == from.persistentModelID }
    }

    public static func parent(of goal: Goal, edges: [Edge]) -> Goal? {
        seqEdges(edges).first { $0.to?.persistentModelID == goal.persistentModelID }?.from
    }
}
