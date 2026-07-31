import SwiftUI
import TwigCore

/// 枝干完全展开（画板态）：贝塞尔枝干从锚点生长 + 圆形玻璃节点。
/// 悬停节点放大并浮出任务面板（勾选/添加/拖动提示），沿交叉轴拖动节点改排期
struct BranchView: View {
    let appState: AppState

    /// 节点标签/悬停面板会画出布局包围盒，四周留白避免被窗口裁切
    private let slackX: CGFloat = 110
    private let slackY: CGFloat = 48

    @State private var draggingNodeID: UUID?
    @State private var dragOffset: CGSize = .zero
    @State private var hoveredNodeID: UUID?
    @State private var hoverExitTask: _Concurrency.Task<Void, Never>?
    @State private var growProgress: CGFloat = 0

    var body: some View {
        let tuning = appState.branchTuning
        let anchor: CGPoint = switch tuning.direction {
        case .right, .left: CGPoint(x: 0, y: 32)
        case .down, .up: CGPoint(x: 190, y: 0)   // 从横条中点向上/下
        }
        let layout = BranchLayout.compute(
            projects: appState.taskStore.allProjects(),
            anchor: anchor,
            tuning: tuning
        )
        // 交叉轴单位向量（节点错开方向，与 BranchLayout 的 cross 一致）：拖节点沿此轴改排期
        let cross: CGPoint = switch tuning.direction {
        case .right: CGPoint(x: 0, y: 1)
        case .left: CGPoint(x: 0, y: -1)
        case .down: CGPoint(x: -1, y: 0)
        case .up: CGPoint(x: 1, y: 0)
        }
        let reported = CGSize(width: layout.contentSize.width + slackX * 2,
                              height: max(layout.contentSize.height + slackY * 2, 120))

        // 布局输出已按包围盒归一化（节点/边/锚点全部落在 [0, contentSize] 内），直接画
        ZStack(alignment: .topLeading) {
            // 点击空白收起
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { appState.widgetState = .collapsed }

            Canvas { ctx, _ in
                for edge in layout.edges {
                    var path = Path()
                    path.move(to: edge.from)
                    path.addCurve(to: edge.to, control1: edge.c1, control2: edge.c2)
                    let color = Color(hex: edge.colorHex) ?? .gray
                    ctx.stroke(
                        path.trimmedPath(from: 0, to: growProgress),
                        with: .color(color.opacity(edge.faded ? 0.4 : 0.85)),
                        style: StrokeStyle(
                            lineWidth: edge.faded ? 1.5 : 2,
                            lineCap: .round,
                            dash: edge.dashed ? [4, 6] : []
                        )
                    )
                }
            }

            ForEach(layout.nodes) { node in
                let isDragging = draggingNodeID == node.id
                let dragDelta = isDragging
                    ? dragOffset.width * cross.x + dragOffset.height * cross.y
                    : 0
                GoalNodeCircle(node: node, direction: layout.direction)
                    .contentShape(Circle())
                    .onHover { nodeHover($0, id: node.id) }
                    .scaleEffect(hoveredNodeID == node.id && !isDragging ? 1.15 : 1)
                    .opacity(isDragging ? 0.9 : node.opacity * growProgress)
                    .position(x: node.center.x + cross.x * dragDelta,
                              y: node.center.y + cross.y * dragDelta)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                draggingNodeID = node.id
                                dragOffset = value.translation
                            }
                            .onEnded { value in
                                draggingNodeID = nil
                                dragOffset = .zero
                                let delta = value.translation.width * cross.x
                                    + value.translation.height * cross.y
                                appState.moveGoal(nodeID: node.id, verticalDelta: delta)
                            }
                    )
                    .onTapGesture { }   // 吞掉单击，避免穿透到底层触发收起
                    .zIndex(1)
            }

            if draggingNodeID == nil,
               let hoveredID = hoveredNodeID,
               let node = layout.nodes.first(where: { $0.id == hoveredID }) {
                NodeHoverPanel(appState: appState, node: node)
                    .onHover { nodeHover($0, id: node.id) }
                    .position(panelPosition(for: node, in: layout.contentSize))
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height)
        .padding(.horizontal, slackX)
        .padding(.vertical, slackY)
        .frame(width: max(560, reported.width), height: reported.height)
        .animation(.easeOut(duration: 0.15), value: hoveredNodeID)
        .animation(.easeInOut(duration: 0.25), value: layout.nodes)
        .onAppear {
            appState.branchContentSize = reported
            // 枝干从锚点生长出来
            withAnimation(.easeOut(duration: 0.3)) { growProgress = 1 }
        }
        .onChange(of: layout.contentSize) { _, _ in
            appState.branchContentSize = reported
        }
    }

    /// 节点/面板悬停：进入立即记录，离开延迟 0.2s 再清（给指针从节点移到面板留时间）
    private func nodeHover(_ inside: Bool, id: UUID) {
        guard draggingNodeID == nil else { return }
        hoverExitTask?.cancel()
        hoverExitTask = nil
        if inside {
            hoveredNodeID = id
        } else {
            hoverExitTask = _Concurrency.Task { @MainActor in
                try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                guard !_Concurrency.Task.isCancelled else { return }
                if hoveredNodeID == id { hoveredNodeID = nil }
            }
        }
    }

    /// 面板默认浮在节点下方，下方空间不足（节点在下半区）时翻到上方；水平方向夹取在可视范围内
    private func panelPosition(for node: BranchNode, in size: CGSize) -> CGPoint {
        let panelW: CGFloat = 230
        let panelH: CGFloat = 180
        let minCX = panelW / 2 - slackX + 12
        let maxCX = size.width - panelW / 2 + slackX - 12
        let x = min(max(node.center.x, minCX), max(minCX, maxCX))
        let below = node.center.y < size.height * 0.55
        let y = below
            ? node.center.y + 22 + 10 + panelH / 2
            : node.center.y - 22 - 10 - panelH / 2
        return CGPoint(x: x, y: y)
    }
}

/// 圆形目标节点：约 44pt 玻璃圆（ultraThinMaterial 底 + 项目色 2pt 描边）。
/// 短期目标中心实心色点，中长期虚线描边；标题按方向自适应：right/left 放侧边，up/down 放下边
private struct GoalNodeCircle: View {
    let node: BranchNode
    let direction: BranchDirection

    static let diameter: CGFloat = 44

    private var color: Color { Color(hex: node.colorHex) ?? .gray }

    var body: some View {
        Circle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: node.dashed ? [4, 3] : []))
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                if !node.dashed {
                    Circle().fill(color).frame(width: 10, height: 10)
                }
            }
            .overlay(alignment: labelAlignment) {
                label.offset(labelOffset)
            }
            .frame(width: Self.diameter, height: Self.diameter)
    }

    private var labelAlignment: Alignment {
        switch direction {
        case .right: .leading
        case .left: .trailing
        case .down, .up: .top
        }
    }

    private var labelOffset: CGSize {
        switch direction {
        case .right: CGSize(width: Self.diameter + 8, height: 0)
        case .left: CGSize(width: -(Self.diameter + 8), height: 0)
        case .down, .up: CGSize(width: 0, height: Self.diameter + 6)
        }
    }

    private var label: some View {
        VStack(spacing: 1) {
            Text(node.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(node.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 130)
    }
}

/// 悬停节点浮出的玻璃小面板：未完成任务（≤5 条，可点击勾选）+ 添加任务 + 可拖动提示
private struct NodeHoverPanel: View {
    let appState: AppState
    let node: BranchNode

    @State private var isAdding = false
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var openTasks: [TwigCore.Task] {
        appState.openTasks(forNodeID: node.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: node.colorHex) ?? .gray)
                    .frame(width: 8, height: 8)
                Text(node.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("⇄")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .help("沿枝干拖动节点可调整排期")
                Button {
                    isAdding = true
                    inputFocused = true
                } label: {
                    Text("＋")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("添加任务")
            }
            ForEach(openTasks, id: \.persistentModelID) { task in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: node.colorHex) ?? .gray)
                    Text(task.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.taskStore.toggleTask(task)
                    appState.exportSnapshot()
                }
            }
            if openTasks.isEmpty && !isAdding {
                Text("暂无未完成任务")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if isAdding {
                TextField("新任务，Enter 添加 / Esc 取消", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .onExitCommand {
                        draft = ""
                        isAdding = false
                    }
            }
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.5), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { }   // 吞掉空白处点击，避免穿透触发收起
    }

    private func submit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !title.isEmpty else {
            isAdding = false
            return
        }
        appState.addTask(toNodeID: node.id, title: title)
    }
}
