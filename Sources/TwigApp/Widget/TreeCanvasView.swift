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
        var pullGrabOffset: CGSize = .zero   // 本次拔树起手时的树偏移（回弹半途续拔用）
    }

    @State private var physics = PhysicsBox()
    @State private var movingGoal: Goal?
    @State private var dragOrigin: CGPoint?
    /// 节点拖动进入时的 custom 状态（微拖 < 8pt 松手要还原，不钉死自动布局）
    @State private var dragSavedCustom: (x: Double?, y: Double?)?
    @State private var newNodeTitle = ""
    @FocusState private var addFieldFocused: Bool

    private var rect: CGRect { CGRect(origin: .zero, size: size) }
    /// 画板顶部安全区：只留少量呼吸边距。
    /// 原 70pt 是给今日浮层让位，但浮层是临时 overlay（z 序压过节点、关闭即还地），
    /// 常驻的大安全区会把根节点推离画布顶边几百 px——原型里向下模式根贴在土壤线附近
    static let peekSafeZone: CGFloat = 12
    /// 节点布局/土线使用的矩形（顶部扣掉安全区）
    private var layoutRect: CGRect {
        CGRect(x: rect.minX, y: rect.minY + Self.peekSafeZone,
               width: rect.width, height: max(0, rect.height - Self.peekSafeZone))
    }
    private var isVertical: Bool {
        appState.pullDirection == .up || appState.pullDirection == .down
    }

    var body: some View {
        // 模块内有同名 Main/TimelineView，必须全限定
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 60)) { context in
            let _ = tickIfNeeded(context.date)   // 实现注：按时间戳幂等驱动，body 计算前先推一帧
            let data = appState.goalsAndEdges()
            let positions = currentPositions()
            // 非激活面板收不到 SwiftUI onHover：每帧轮询光标位置驱动悬停 HUD（幂等按状态迁移）
            let _ = syncHoverWithMouse(goals: data.goals, positions: positions)
            // 布局包围盒（只算可见节点：已出土 + 手动摆放； buried 节点在画布外不算），
            // 变化时回写 AppState，TreeWidgetController 据此扩/收窗
            let bounds = contentBounds(goals: data.goals)
            let buriedCount = data.goals.filter { !$0.revealed }.count
            ZStack(alignment: .topLeading) {
                // 空白命中层（垫底）：点空白关闭详情弹卡 / 内联输入卡
                Color.white.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.leafTask = nil
                        appState.addingNodeNear = nil
                    }
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
                            .onHover { inside in nodeHover(goal, inside: inside) }
                    }
                }
                HoverHud(appState: appState, positions: positions,
                         onPullStart: startPull, onPullDrag: pullDrag, onPullEnd: endPull,
                         onHudHover: hudHover, onLinkingChanged: linkingChanged)
                TaskLeafPopover(appState: appState, positions: positions)
                // 埋土提示：土线侧一行灰字（仅当还有未出土节点）
                if buriedCount > 0 {
                    Text("土里还有 \(buriedCount) 个目标")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .position(buriedHintPos())
                }
                // HUD ＋ 的内联输入卡：anchor 节点下方，Enter 创建，Esc/失焦取消
                if let anchor = appState.addingNodeNear,
                   let anchorFrame = positions[anchor.persistentModelID] {
                    addNodeCard(anchor: anchor, frame: anchorFrame)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // 画布在窗口坐标系（.global = 窗口内容区，左上角原点）的 frame：
            // 光标轮询把窗口坐标换算成画布局部坐标用（写引用盒，不触发状态刷新）
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { newFrame in
                hoverBox.canvasFrameInWindow = newFrame
            }
            .onExitCommand {
                appState.leafTask = nil
                appState.addingNodeNear = nil
            }
            .onChange(of: appState.addingNodeNear?.persistentModelID) { _, _ in
                newNodeTitle = ""   // 换锚点/重新打开都从空标题起
            }
            .onChange(of: bounds, initial: true) { _, newValue in
                appState.reportedTreeBounds = newValue
            }
        }
    }

    // MARK: - 内联新增节点卡（HUD ＋ 按钮的消费者）

    @ViewBuilder
    private func addNodeCard(anchor: Goal, frame: CGRect) -> some View {
        TextField("新分支名，Enter 创建", text: $newNodeTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(width: 200)
            .background(.white.opacity(0.85))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .focused($addFieldFocused)
            .onSubmit { commitAddNode(near: anchor) }
            .onExitCommand { cancelAddNode() }
            .onChange(of: addFieldFocused) { _, focused in
                // 失焦即关闭（卡片是有焦点的临时态；提交/取消本身幂等，重复清场无害）
                if !focused { cancelAddNode() }
            }
            .position(x: frame.midX, y: frame.maxY + 64)
            .onAppear { addFieldFocused = true }
    }

    private func commitAddNode(near anchor: Goal) {
        let title = newNodeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, let newGoal = appState.addGoalNode(near: anchor, title: title) {
            appState.reveal(newGoal)   // 新节点立刻出土可见（短期默认已 revealed，reveal 幂等）
        }
        cancelAddNode()
    }

    private func cancelAddNode() {
        newNodeTitle = ""
        appState.addingNodeNear = nil
    }

    /// 埋土提示位置：随 pullDirection 贴土线侧
    private func buriedHintPos() -> CGPoint {
        switch appState.pullDirection {
        case .up:    return CGPoint(x: rect.midX, y: rect.maxY - 12)
        case .down:  return CGPoint(x: rect.midX, y: rect.minY + 12)
        case .left:  return CGPoint(x: rect.minX + 48, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX - 48, y: rect.midY)
        }
    }

    /// 可见节点的包围盒尺寸（卡片 150×48 全计入；用基础布局位，不含拔树瞬态偏移）
    private func contentBounds(goals: [Goal]) -> CGSize {
        let base = appState.placements(in: layoutRect)
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var found = false
        for g in goals where g.revealed || g.customX != nil {
            guard let p = base[g.persistentModelID] else { continue }
            found = true
            // 右侧要留出小卫星（期限tag+进度条+红点 ≈ 90px）：节点半宽 75 + 卫星 90 + 抖动 22
            maxX = max(maxX, p.x + 75 + 90)
            maxY = max(maxY, p.y + 24)
        }
        guard found else { return CGSize(width: 720, height: 400) }   // 全埋：给默认画板
        // 布局从画布左上绝对定位（含顶部安全区与左侧内边距），包围盒必须从画布原点
        // 量到最右/最下节点边缘——若只报"节点跨度"，窗口会比布局矮/窄，
        // 深层节点被窗框裁掉、根节点看起来也没贴在设计位置上
        return CGSize(width: maxX + 24, height: maxY + 24)
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
            // 出土判定：组件内、seq 父已出土、未出土节点；buriedDepth 传纯埋深（slack 归 checkReveal 内部）
            let data = appState.goalsAndEdges()
            let base = appState.placements(in: layoutRect)
            let soil = soilLine()
            for g in data.goals where !g.revealed && appState.pullComponent.contains(g.persistentModelID) {
                if let parent = TreeTopology.parent(of: g, edges: data.edges), !parent.revealed { continue }
                guard let p = base[g.persistentModelID] else { continue }
                let buried = isVertical ? abs(p.y - soil) : abs(p.x - soil)
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
        let base = appState.placements(in: layoutRect)
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
        TreeGeom.geom(for: appState.pullDirection, rect: layoutRect).soil
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
                    dragSavedCustom = (goal.customX, goal.customY)   // 微拖松手要还原
                    appState.hoverLockedForDrag = true   // 拖动时隐藏 HUD
                }
                guard let origin = dragOrigin else { return }
                goal.customX = Double(origin.x + value.translation.width)
                goal.customY = Double(origin.y + value.translation.height)
            }
            .onEnded { value in
                let dist = hypot(value.translation.width, value.translation.height)
                if dist < 8 {
                    // 微拖不钉死自动布局：还原进入拖动前的 custom 状态（可能原本就是 nil）
                    goal.customX = dragSavedCustom?.x
                    goal.customY = dragSavedCustom?.y
                    try? appState.container.mainContext.save()
                } else {
                    appState.setCustomPosition(goal, x: CGFloat(goal.customX ?? 0), y: CGFloat(goal.customY ?? 0))
                }
                dragSavedCustom = nil
                movingGoal = nil
                dragOrigin = nil
                appState.hoverLockedForDrag = false
            }
    }

    private func basePos(of goal: Goal) -> CGPoint {
        appState.placements(in: layoutRect)[goal.persistentModelID] ?? .zero
    }

    // MARK: - 悬停防抖（180ms：节点 → HUD 之间留路；拔树/拉线期间悬停上下文锁定）

    /// 悬停防抖的暂存（引用类型，理由同 PhysicsBox：onHover 在 body 求值外触发，
    /// 但延迟清场的 Task 闭包里读它不能是 @State 值拷贝）
    private final class HoverBox {
        var gen = 0          // 悬停事件代次：每次进出 +1，过期代次的延迟清场自动作废
        var linking = false  // 挂点拉线进行中：悬停锁定在源节点，经过的节点不抢悬停
        var onHud = false    // 光标在 HUD 上（进出事件顺序无保证，清场时以此兜底）
        /// 画布在窗口坐标系的 frame（onGeometryChange 回写）：光标轮询换算局部坐标用
        var canvasFrameInWindow: CGRect = .zero
        /// 光标轮询当前命中的节点（只在迁移时触发进出，光标静止不重复触发）
        var mouseHitID: PersistentIdentifier?
    }

    @State private var hoverBox = HoverBox()

    // MARK: - 光标轮询悬停（NSPanel 非激活时 SwiftUI onHover 不触发，
    // 每帧读 NSEvent.mouseLocation → 命中节点/HUD 区域，迁移时走与 onHover 相同的防抖管线）

    private func syncHoverWithMouse(goals: [Goal], positions: [PersistentIdentifier: CGRect]) {
        let canvasFrame = hoverBox.canvasFrameInWindow
        guard canvasFrame.width > 0 else { return }
        var hitID: PersistentIdentifier?
        var onHud = false
        if let win = appState.widgetMouseProvider?(), canvasFrame.contains(win) {
            let local = CGPoint(x: win.x - canvasFrame.minX, y: win.y - canvasFrame.minY)
            // 节点命中（外扩 2pt 容错）
            hitID = positions.first(where: { $0.value.insetBy(dx: -2, dy: -2).contains(local) })?.key
            // HUD 命中：悬停节点上下各扩 40（上排钮在 minY-18、叶子在 maxY+18），
            // 横向放宽到钮排/叶子排宽度，节点 → HUD 的间隙靠这个跨过
            if hitID == nil, let hovered = appState.hoveredGoal,
               let hf = positions[hovered.persistentModelID] {
                onHud = hf.insetBy(dx: -80, dy: -40).contains(local)
            }
        }
        if onHud != hoverBox.onHud { hudHover(onHud) }
        guard hitID != hoverBox.mouseHitID else { return }
        let prevID = hoverBox.mouseHitID
        hoverBox.mouseHitID = hitID
        if let prevID {
            if let prev = goals.first(where: { $0.persistentModelID == prevID }) {
                nodeHover(prev, inside: false)
            } else {
                // 悬停目标已被删除（HUD 🗑）：按退出处理，走防抖清场
                hoverBox.gen &+= 1
                scheduleHoverClear(gen: hoverBox.gen)
            }
        }
        if let hitID, let goal = goals.first(where: { $0.persistentModelID == hitID }) {
            nodeHover(goal, inside: true)
        }
    }

    private func nodeHover(_ goal: Goal, inside: Bool) {
        if hoverBox.linking { return }                          // 拉线经过的节点不抢悬停
        if inside && appState.pullSession != nil { return }     // 拔树中不切悬停目标
        hoverBox.gen &+= 1
        if inside {
            appState.hoveredGoal = goal
        } else {
            scheduleHoverClear(gen: hoverBox.gen)
        }
    }

    /// HUD 自身悬停：进入即作废待执行的清场（节点 → HUD 的 5px 间隙靠这个跨过）
    private func hudHover(_ inside: Bool) {
        hoverBox.onHud = inside
        hoverBox.gen &+= 1
        if !inside { scheduleHoverClear(gen: hoverBox.gen) }
    }

    private func linkingChanged(_ linking: Bool) {
        hoverBox.linking = linking
        hoverBox.gen &+= 1
    }

    private func scheduleHoverClear(gen: Int) {
        let box = hoverBox
        _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .milliseconds(180))
            guard box.gen == gen, !box.linking, !box.onHud, appState.pullSession == nil else { return }
            appState.hoveredGoal = nil
        }
    }

    // MARK: - 拔树入口（HoverHud 的 ⇄ 把手回调）

    private func startPull(_ goal: Goal) {
        physics.springT = nil   // 打断进行中的回弹
        let comp = TreeTopology.component(of: goal, edges: appState.goalsAndEdges().edges)
        appState.pullComponent = comp.ids
        appState.pullDepths = comp.depths
        appState.pullProject = goal.project
        var session = PullSession()
        // 回弹半途再拔：新 session 从当前树偏移续起（offset 与 target 同起点），避免瞬移
        session.offset = appState.treeOffset
        session.targetOffset = appState.treeOffset
        appState.pullSession = session
        physics.pullGrabOffset = appState.treeOffset
    }

    // HUD 把手 DragGesture.onChanged 调这个：
    private func pullDrag(_ translation: CGSize) {
        guard var session = appState.pullSession else { return }
        let grab = physics.pullGrabOffset
        session.targetOffset = CGSize(width: grab.width + translation.width * 0.9,
                                      height: grab.height + translation.height * 0.9)
        appState.pullSession = session
    }

    private func endPull() {
        appState.springStartOffset = appState.treeOffset
        physics.springT = 0
        appState.pullSession = nil
        // pullComponent/pullDepths 保留到回弹播完（tick 里清），树才能跟着偏移弹回
        // 拔树期间拖离 HUD 的清场被 pullSession 守卫丢弃，松手后补调度一次；
        // 光标若仍在 HUD 上，清场闭包的 onHud/linking 守卫会拦住，不会误清
        scheduleHoverClear(gen: hoverBox.gen)
    }
}
