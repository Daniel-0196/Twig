import SwiftData
import SwiftUI
import TwigCore

/// 悬停 HUD：上排功能钮 + 下排叶子 + 出挂点（与节点同一悬停上下文）
/// 180ms 防抖在 TreeCanvasView（节点 → HUD 之间留路）；拔树/拉线期间悬停上下文锁定
struct HoverHud: View {
    let appState: AppState
    let positions: [PersistentIdentifier: CGRect]
    /// 由 TreeCanvasView 注入（⇄ 拔树把手）
    var onPullStart: ((Goal) -> Void)?
    var onPullDrag: ((CGSize) -> Void)?
    var onPullEnd: (() -> Void)?
    /// HUD 自身悬停回传（节点 → HUD 移动防抖用）；挂点松手落空时也用它延迟清场
    var onHudHover: ((Bool) -> Void)?
    /// 挂点拉线开始/结束（true 期间悬停锁定在源节点，不切换不清除）
    var onLinkingChanged: ((Bool) -> Void)?

    var body: some View {
        Group {
            if let goal = appState.hoveredGoal, !appState.hoverLockedForDrag,
               let frame = positions[goal.persistentModelID] {
                let color = Color(hex: goal.project?.colorHint ?? "#D97757") ?? .orange
                // 上排功能钮
                HStack(spacing: 6) {
                    hudButton("＋", color: Color(red: 0.49, green: 0.61, blue: 0.46), help: "新增分支") {
                        #if DEBUG
                        TwigEventLog.log("HUD ＋ tapped \(goal.title)")
                        #endif
                        appState.addingNodeNear = goal   // TreeCanvasView 在该节点旁渲染内联输入卡
                    }
                    hudButton("🗑", color: .secondary, help: "删除") {
                        appState.hoveredGoal = nil   // 先清悬停，避免悬停目标指向已删模型
                        appState.deleteGoalTree(goal)
                    }
                    pullHandle(color: Color(red: 0.62, green: 0.76, blue: 0.92), goal: goal)
                    if TreeTopology.isRoot(goal, edges: appState.goalsAndEdges().edges) {
                        hudButton("↺", color: Color(red: 0.91, green: 0.76, blue: 0.48), help: "重置这棵树") {
                            if let p = goal.project { appState.resetTree(p) }
                        }
                    }
                }
                .position(x: frame.midX, y: frame.minY - 18)

                // 下排叶子
                LeafRow(goal: goal, color: color, appState: appState)
                    .position(x: frame.midX, y: frame.maxY + 18)

                // 出挂点
                PortDot(appState: appState, goal: goal, frame: frame,
                        positionsRef: positions,
                        onLinkingChanged: onLinkingChanged,
                        onHudHover: onHudHover)
            }
        }
        // 不挂 .onHover：它会毒化画布命中测试（见 TreeCanvasView 节点卡的二分注释）；
        // HUD 悬停由 TreeCanvasView 光标轮询的区域判定驱动（syncHoverWithMouse → hudHover）
    }

    private func hudButton(_ label: String, color: Color, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.78))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pullHandle(color: Color, goal: Goal) -> some View {
        Text("⇄").font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.78))
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
            .help("拔树（按住沿方向拽）")
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if appState.pullSession == nil { onPullStart?(goal) }
                        onPullDrag?(value.translation)
                    }
                    .onEnded { _ in onPullEnd?() }
            )
    }
}

/// 叶子排：任务关键字（≤2 字），点击开任务详情
struct LeafRow: View {
    let goal: Goal
    let color: Color
    let appState: AppState

    private var openTasks: [TwigCore.Task] {
        goal.tasks.filter { !$0.isDone }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(openTasks.prefix(6), id: \.persistentModelID) { task in
                Text(String(task.title.prefix(2)))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.24, green: 0.23, blue: 0.21))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.white.opacity(0.8))
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(topLeadingRadius: 12, bottomLeadingRadius: 3,
                                     bottomTrailingRadius: 12, topTrailingRadius: 12))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 3,
                                               bottomTrailingRadius: 12, topTrailingRadius: 12)
                            .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1)
                    )
                    .onTapGesture { appState.leafTask = (task, goal) }
                    .help(task.title)
            }
            if openTasks.count > 6 {
                Text("+\(openTasks.count - 6)").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

/// 出挂点：按住拖到另一节点建立顺序关联
struct PortDot: View {
    let appState: AppState
    let goal: Goal
    let frame: CGRect
    var positionsRef: [PersistentIdentifier: CGRect] = [:]
    var onLinkingChanged: ((Bool) -> Void)?
    var onHudHover: ((Bool) -> Void)?
    @State private var dragPoint: CGPoint?

    var body: some View {
        let portPos = CGPoint(x: frame.maxX, y: frame.midY)   // 简化：恒右侧；方向化后续迭代
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color(red: 0.65, green: 0.64, blue: 0.62), lineWidth: 1.5))
            .frame(width: 10, height: 10)
            // 橡皮线画在 10×10 overlay 的局部坐标里（圆心 (5,5) = 画布 portPos；overlay 不裁切，线可探出）
            .overlay {
                if let dragPoint {
                    Path { p in
                        p.move(to: CGPoint(x: 5, y: 5))
                        p.addLine(to: CGPoint(x: dragPoint.x - portPos.x + 5,
                                              y: dragPoint.y - portPos.y + 5))
                    }
                    .stroke(Color(red: 0.65, green: 0.64, blue: 0.62).opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .position(portPos)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragPoint == nil { onLinkingChanged?(true) }
                        dragPoint = CGPoint(x: portPos.x + value.translation.width,
                                            y: portPos.y + value.translation.height)
                    }
                    .onEnded { value in
                        // 实现注：DragGesture.location 在挂点自身 10×10 局部坐标系，
                        // 不能拿去和画布 frame 比；松手点 = portPos + translation（与 positionsRef 同坐标系）
                        let drop = CGPoint(x: portPos.x + value.translation.width,
                                           y: portPos.y + value.translation.height)
                        // 命中检测：松手点在某个节点 frame 内 → 建边
                        var hitAny = false
                        for (id, target) in positionsRef where target.contains(drop) {
                            hitAny = true
                            if let t = appState.goalsAndEdges().goals.first(where: { $0.persistentModelID == id }),
                               t.persistentModelID != goal.persistentModelID {
                                appState.addEdge(from: goal, to: t)
                                appState.hoveredGoal = t   // 悬停移交目标节点（拉线期间锁定在源节点）
                            }
                            break
                        }
                        dragPoint = nil
                        onLinkingChanged?(false)
                        if !hitAny { onHudHover?(false) }   // 落空：走 180ms 防抖清场
                    }
            )
    }
}
