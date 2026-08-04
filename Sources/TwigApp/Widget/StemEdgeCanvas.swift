import SwiftData
import SwiftUI
import TwigCore

/// 茎线画布：多层锥度 + 土壤弯折 + 悬停聚焦
struct StemEdgeCanvas: View {
    let edges: [TwigCore.Edge]
    let positions: [PersistentIdentifier: CGRect]
    let direction: PullDirection
    let soilLine: CGFloat
    var focusGoal: PersistentIdentifier? = nil
    var crossPull: CGFloat = 0
    var crossVel: CGFloat = 0

    var body: some View {
        // Canvas 整体是一个不透明命中体：不关掉会把下方空白层/节点/手势全部挡死
        // （二分定位：l1 空白层可点，加入本层后整窗点击全灭）。双击连线由 edgeHitLayer 负责
        Canvas { ctx, _ in
            for edge in edges {
                guard let from = edge.from, let to = edge.to,
                      let a = positions[from.persistentModelID],
                      let b = positions[to.persistentModelID] else { continue }
                let isSeq = edge.type == .sequence
                // 引用线：深灰细虚线（原型 rgba(31,30,29,0.28)）；白底上白色不可见
                let color = isSeq ? Color(hex: from.project?.colorHint ?? "#D97757") ?? .orange
                                  : Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.28)
                let hot = focusGoal == nil
                    || from.persistentModelID == focusGoal
                    || to.persistentModelID == focusGoal
                let out = outPort(a)
                let end = inPort(b)

                if to.revealed || !isSeq {
                    let length = hypot(end.x - out.x, end.y - out.y)
                    let bow = bow(for: edge, length: length)
                    drawStem(ctx: ctx, from: out, to: end, color: color, hot: hot,
                             dashed: !isSeq, bow: bow)
                } else {
                    drawCrossing(ctx: ctx, from: out, to: end, color: color, hot: hot)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 挂点
    private var sign: CGPoint {   // 链条朝向单位向量
        switch direction {
        case .up: return CGPoint(x: 0, y: 1)
        case .down: return CGPoint(x: 0, y: -1)
        case .left: return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        }
    }
    private func outPort(_ r: CGRect) -> CGPoint {
        direction == .up ? CGPoint(x: r.midX, y: r.maxY)
        : direction == .down ? CGPoint(x: r.midX, y: r.minY)
        : direction == .left ? CGPoint(x: r.minX, y: r.midY)
        : CGPoint(x: r.maxX, y: r.midY)
    }
    private func inPort(_ r: CGRect) -> CGPoint {
        direction == .up ? CGPoint(x: r.midX, y: r.minY)
        : direction == .down ? CGPoint(x: r.midX, y: r.maxY)
        : direction == .left ? CGPoint(x: r.maxX, y: r.midY)
        : CGPoint(x: r.minX, y: r.midY)
    }

    // MARK: - 弯曲（藤蔓张力）
    private func bow(for edge: TwigCore.Edge, length: CGFloat) -> CGFloat {
        let hash = Double(abs(edge.persistentModelID.hashValue % 1000)) / 1000.0
        let bowStatic = min(8, length * 0.05) * (hash > 0.5 ? 1 : -1)
        let bowDyn = max(-55, min(55, crossVel * 6 + crossPull * 0.25))
        return bowStatic + bowDyn
    }

    private func curve(from out: CGPoint, to end: CGPoint, bow: CGFloat) -> Path {
        let g = sign
        let perp = CGPoint(x: -g.y * bow, y: g.x * bow)
        let norm: CGFloat = 40
        let m1 = CGPoint(x: out.x + g.x * norm + perp.x * 0.8, y: out.y + g.y * norm + perp.y * 0.8)
        let m2 = CGPoint(x: end.x - g.x * norm + perp.x, y: end.y - g.y * norm + perp.y)
        var p = Path()
        p.move(to: out)
        p.addCurve(to: end, control1: m1, control2: m2)
        return p
    }

    // MARK: - 多层锥度茎
    private func drawStem(ctx: GraphicsContext, from: CGPoint, to: CGPoint,
                          color: Color, hot: Bool, dashed: Bool, bow: CGFloat) {
        let path = curve(from: from, to: to, bow: bow)
        if dashed {
            ctx.stroke(path, with: .color(color.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            return
        }
        let dim: Double = hot ? 1 : 0.3
        // 4 层叠加锥度：细笔贯通、粗笔只覆盖根部（trim 比例）
        let covers: [CGFloat] = [1, 0.76, 0.52, 0.28]
        for (i, cover) in covers.enumerated() {
            let k = CGFloat(i) / CGFloat(covers.count - 1)
            let width = (0.8 + (3 - 0.8) * k) * (hot ? 1.15 : 1)
            let opacity = (0.4 + (0.9 - 0.4) * k) * dim
            ctx.stroke(path.trimmedPath(from: 0, to: cover),
                       with: .color(color.opacity(opacity)),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // 入点消融圆点
        let dot = Path(ellipseIn: CGRect(x: to.x - 2.5, y: to.y - 2.5, width: 5, height: 5))
        ctx.fill(dot, with: .color(color.opacity(min(1, 0.4 * 1.6) * dim)))
    }

    // MARK: - 跨界弯折（土线）
    private func drawCrossing(ctx: GraphicsContext, from out: CGPoint, to end: CGPoint,
                              color: Color, hot: Bool) {
        let mainOut = direction == .up || direction == .down ? out.y : out.x
        let mainEnd = direction == .up || direction == .down ? end.y : end.x
        let t = max(0.05, min(0.95, (soilLine - mainOut) / (mainEnd - mainOut)))
        let s = CGPoint(x: out.x + (end.x - out.x) * t, y: out.y + (end.y - out.y) * t)
        let g = sign
        let bow = min(8, hypot(end.x - out.x, end.y - out.y) * 0.05)
        let perp = CGPoint(x: -g.y * bow, y: g.x * bow)
        // 地上段：锥度茎到土线
        var above = Path()
        above.move(to: out)
        above.addCurve(to: s,
                       control1: CGPoint(x: out.x + g.x * 40 + perp.x * 0.7, y: out.y + g.y * 40 + perp.y * 0.7),
                       control2: CGPoint(x: s.x - g.x * 24 + perp.x * 0.9, y: s.y - g.y * 24 + perp.y * 0.9))
        let dim: Double = hot ? 1 : 0.3
        for (i, cover) in [CGFloat(1), 0.76, 0.52, 0.28].enumerated() {
            let k = CGFloat(i) / 3
            ctx.stroke(above.trimmedPath(from: 0, to: cover),
                       with: .color(color.opacity((0.4 + 0.4 * k) * dim)),
                       style: StrokeStyle(lineWidth: (1 + 1.6 * k), lineCap: .round))
        }
        // 地下段：虚线扎进土壤
        var below = Path()
        below.move(to: s)
        below.addCurve(to: end,
                       control1: CGPoint(x: s.x + g.x * 30, y: s.y + g.y * 30),
                       control2: CGPoint(x: end.x - g.x * 40, y: end.y - g.y * 40))
        ctx.stroke(below, with: .color(color.opacity(0.45)),
                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
    }
}
