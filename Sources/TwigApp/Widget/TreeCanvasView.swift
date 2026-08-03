import SwiftData
import SwiftUI
import TwigCore

/// 树画布：节点 + 茎线 + 手势路由（每帧驱动）
struct TreeCanvasView: View {
    let appState: AppState
    let size: CGSize

    /// 每帧物理的暂存（引用类型）：tick 在 TimelineView content（body 求值期间）被调，
    /// 若用 @State 存这些值会触发 "Modifying state during view update" 运行时告警并自触发渲染
    private final class PhysicsBox {
        var lastTickDate: Date?
        var springT: CGFloat?   // 回弹进行中（0→1）
    }

    @State private var physics = PhysicsBox()
    @State private var movingGoal: Goal?
    @State private var dragOrigin: CGPoint?

    private var rect: CGRect { CGRect(origin: .zero, size: size) }
    private var isVertical: Bool {
        appState.pullDirection == .up || appState.pullDirection == .down
    }

    var body: some View {
        // 模块内有同名 Main/TimelineView，必须全限定
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 60)) { context in
            let _ = tickIfNeeded(context.date)   // 实现注：按时间戳幂等驱动，body 计算前先推一帧
            let data = appState.goalsAndEdges()
            let positions = currentPositions()
            ZStack(alignment: .topLeading) {
                StemEdgeCanvas(edges: data.edges,
                               positions: positions,
                               direction: appState.pullDirection,
                               soilLine: soilLine(),
                               focusGoal: appState.hoveredGoal?.persistentModelID,
                               crossPull: crossPull,
                               crossVel: crossVel)
                edgeHitLayer(edges: data.edges, positions: positions)
                ForEach(data.goals, id: \.persistentModelID) { goal in
                    if let frame = positions[goal.persistentModelID] {
                        NodeCardView(goal: goal,
                                     color: Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange,
                                     isBuried: !goal.revealed,
                                     isFocusing: appState.timerStore.activeTask?.goal?.persistentModelID == goal.persistentModelID)
                            .position(x: frame.midX, y: frame.midY)
                            // 出土时"从土里滑入槽位"（revealed 翻转的那一帧才动画，拔树逐帧不插值）
                            .animation(.spring(duration: 0.45, bounce: 0.2), value: goal.revealed)
                            .gesture(nodeDrag(goal))
                            .onHover { inside in
                                appState.hoveredGoal = inside ? goal : (appState.hoveredGoal == goal ? nil : appState.hoveredGoal)
                            }
                    }
                }
                // Task 9 接入：HoverHud(appState:positions:onPullStart:onPullDrag:onPullEnd:)
                // 三个回调已在本视图实现：startPull(_:) / pullDrag(_:) / endPull()
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    // MARK: - 每帧物理（幂等按时间戳驱动，60fps periodic 本身已是帧节奏）

    private func tickIfNeeded(_ date: Date) {
        guard physics.lastTickDate != date else { return }
        physics.lastTickDate = date
        tick()
    }

    private func tick() {
        if var session = appState.pullSession {
            PullPhysics.step(&session, direction: appState.pullDirection)
            appState.pullSession = session
            appState.treeOffset = session.offset
            // 出土判定：组件内、seq 父已出土、未出土节点；埋深 = |节点主轴坐标 − soil| + 20
            let data = appState.goalsAndEdges()
            let base = appState.placements(in: rect)
            let soil = soilLine()
            for g in data.goals where !g.revealed && appState.pullComponent.contains(g.persistentModelID) {
                if let parent = TreeTopology.parent(of: g, edges: data.edges), !parent.revealed { continue }
                guard let p = base[g.persistentModelID] else { continue }
                let buried = (isVertical ? abs(p.y - soil) : abs(p.x - soil)) + 20
                if PullPhysics.checkReveal(&session, direction: appState.pullDirection, buriedDepth: buried) {
                    appState.pullSession = session
                    appState.reveal(g)
                }
            }
        } else if let t0 = physics.springT {
            // 回弹帧：offset = springStart × (1 − easeOutBack(t))，0.38s 播完
            let t = min(1, t0 + 1.0 / 60.0 / 0.38)
            let e = PullPhysics.springEase(t)
            if t >= 1 {
                physics.springT = nil
                appState.treeOffset = .zero
                appState.pullComponent = []
                appState.pullDepths = [:]
            } else {
                physics.springT = t
                appState.treeOffset = CGSize(width: appState.springStartOffset.width * (1 - e),
                                             height: appState.springStartOffset.height * (1 - e))
            }
        }
    }

    // MARK: - 每帧位置（布局 + 拔树偏移，按 BFS 深度滞后跟随）

    private func currentPositions() -> [PersistentIdentifier: CGRect] {
        // placements 已覆盖手动位置（customX/Y 非空的节点 TreeLayout 原样写入）
        let base = appState.placements(in: rect)
        var frames: [PersistentIdentifier: CGRect] = [:]
        let offset = appState.treeOffset
        for (id, pt) in base {
            var p = pt
            // 拔树与回弹期间组件节点跟随树偏移（pullComponent 保留到回弹播完才清）
            if appState.pullComponent.contains(id) {
                let depth = CGFloat(appState.pullDepths[id] ?? 0)
                let follow = 1 / (1 + depth * 0.25)
                p = CGPoint(x: pt.x + offset.width * follow, y: pt.y + offset.height * follow)
            }
            // 实现注：挂点用节点中心 + 近似半宽半高（75/24），真实尺寸后续手感迭代再精化
            frames[id] = CGRect(x: p.x - 75, y: p.y - 24, width: 150, height: 48)
        }
        return frames
    }

    private func soilLine() -> CGFloat {
        TreeGeom.geom(for: appState.pullDirection, rect: rect).soil
    }

    /// 交叉轴拔力（茎线张力弯曲用）
    private var crossPull: CGFloat {
        guard let s = appState.pullSession else { return 0 }
        return isVertical ? s.offset.width : s.offset.height
    }

    /// 交叉轴本帧速度（茎线张力弯曲用）
    private var crossVel: CGFloat {
        guard let s = appState.pullSession else { return 0 }
        return isVertical ? s.velocity.width : s.velocity.height
    }

    // MARK: - 双击连线命中层（SwiftUI Canvas 无法命中，透明描边路径覆盖）

    @ViewBuilder
    private func edgeHitLayer(edges: [TwigCore.Edge],
                              positions: [PersistentIdentifier: CGRect]) -> some View {
        ForEach(edges, id: \.persistentModelID) { edge in
            if let from = edge.from, let to = edge.to,
               let a = positions[from.persistentModelID],
               let b = positions[to.persistentModelID] {
                Path { p in
                    p.move(to: outPort(a))
                    p.addLine(to: inPort(b))
                }
                .strokedPath(StrokeStyle(lineWidth: 16, lineCap: .round))
                .fill(Color.white.opacity(0.001))   // 近全透明但可命中
                .onTapGesture(count: 2) { appState.toggleEdgeType(edge) }
            }
        }
    }

    // 挂点几何与 StemEdgeCanvas 保持一致（出挂点在链条方向侧，入挂点反侧）
    private func outPort(_ r: CGRect) -> CGPoint {
        switch appState.pullDirection {
        case .up: return CGPoint(x: r.midX, y: r.maxY)
        case .down: return CGPoint(x: r.midX, y: r.minY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        }
    }

    private func inPort(_ r: CGRect) -> CGPoint {
        switch appState.pullDirection {
        case .up: return CGPoint(x: r.midX, y: r.minY)
        case .down: return CGPoint(x: r.midX, y: r.maxY)
        case .left: return CGPoint(x: r.maxX, y: r.midY)
        case .right: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    // MARK: - 节点拖动（普通拖动 = 移动位置，松手写 customX/Y）

    private func nodeDrag(_ goal: Goal) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if movingGoal?.persistentModelID != goal.persistentModelID {
                    movingGoal = goal
                    // 实现注：首次记录拖拽起点，之后 custom = origin + translation（不累加）
                    let base = basePos(of: goal)
                    dragOrigin = CGPoint(x: goal.customX.map { CGFloat($0) } ?? base.x,
                                         y: goal.customY.map { CGFloat($0) } ?? base.y)
                    appState.hoverLockedForDrag = true   // 拖动时隐藏 HUD
                }
                guard let origin = dragOrigin else { return }
                goal.customX = Double(origin.x + value.translation.width)
                goal.customY = Double(origin.y + value.translation.height)
            }
            .onEnded { _ in
                appState.setCustomPosition(goal, x: CGFloat(goal.customX ?? 0), y: CGFloat(goal.customY ?? 0))
                movingGoal = nil
                dragOrigin = nil
                appState.hoverLockedForDrag = false
            }
    }

    private func basePos(of goal: Goal) -> CGPoint {
        appState.placements(in: rect)[goal.persistentModelID] ?? .zero
    }

    // MARK: - 拔树入口（Task 9 HoverHud 的 ⇄ 把手回调，届时接线）

    private func startPull(_ goal: Goal) {
        physics.springT = nil   // 打断进行中的回弹
        let comp = TreeTopology.component(of: goal, edges: appState.goalsAndEdges().edges)
        appState.pullComponent = comp.ids
        appState.pullDepths = comp.depths
        appState.pullProject = goal.project
        appState.pullSession = PullSession()
    }

    // HUD 把手 DragGesture.onChanged 调这个：
    private func pullDrag(_ translation: CGSize) {
        guard var session = appState.pullSession else { return }
        session.targetOffset = CGSize(width: translation.width * 0.9, height: translation.height * 0.9)
        appState.pullSession = session
    }

    private func endPull() {
        appState.springStartOffset = appState.treeOffset
        physics.springT = 0
        appState.pullSession = nil
        // pullComponent/pullDepths 保留到回弹播完（tick 里清），树才能跟着偏移弹回
    }
}
