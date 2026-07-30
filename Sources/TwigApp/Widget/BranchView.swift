import SwiftUI
import TwigCore

/// 枝干完全展开：贝塞尔枝干 + 圆润玻璃块节点；拖动节点改排期
struct BranchView: View {
    let appState: AppState
    @State private var draggingNodeID: UUID?

    var body: some View {
        let tuning = appState.branchTuning
        let anchor: CGPoint = switch tuning.direction {
        case .right: CGPoint(x: 0, y: 32)
        case .left:  CGPoint(x: 0, y: 32)          // 容器内坐标，布局向左延展
        case .down:  CGPoint(x: 190, y: 0)         // 从横条中点向下
        case .up:    CGPoint(x: 190, y: 0)
        }
        let layout = BranchLayout.compute(
            projects: appState.taskStore.allProjects(),
            anchor: anchor,
            tuning: tuning
        )
        // 左/上方向时布局坐标为负向，整体平移进容器正坐标系
        let tx: CGFloat = layout.direction == .left ? layout.contentSize.width : 0
        let ty: CGFloat = layout.direction == .up ? layout.contentSize.height : 0
        ZStack(alignment: .topLeading) {
            Group {
                Canvas { ctx, _ in
                    for edge in layout.edges {
                        var path = Path()
                        path.move(to: edge.from)
                        path.addCurve(to: edge.to, control1: edge.c1, control2: edge.c2)
                        let color = Color(hex: edge.colorHex) ?? .gray
                        ctx.stroke(
                            path,
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
                    GoalNodeBlock(node: node)
                        .position(node.center)
                        .opacity(draggingNodeID == node.id ? 0.9 : node.opacity)
                        .gesture(
                            DragGesture()
                                .onChanged { _ in draggingNodeID = node.id }
                                .onEnded { value in
                                    draggingNodeID = nil
                                    appState.moveGoal(nodeID: node.id, verticalDelta: value.translation.height)
                                }
                        )
                }
            }
            .offset(x: tx, y: ty)
        }
        .frame(
            width: max(560, layout.contentSize.width),
            height: max(layout.contentSize.height, 120)
        )
        .onChange(of: layout.contentSize) { _, size in
            appState.branchContentSize = size
        }
        .onAppear { appState.branchContentSize = layout.contentSize }
        .background(
            Color.clear.contentShape(Rectangle()).onTapGesture {
                appState.widgetState = .collapsed
            }
        )
    }
}

/// 单个目标节点：圆润玻璃块
struct GoalNodeBlock: View {
    let node: BranchNode

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: node.colorHex) ?? .gray)
                .frame(width: 8, height: 8)
            Text(node.title)
                .font(.system(size: 12, weight: .medium))
            Text(node.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(node.dashed ? 0.35 : 0.6),
                        style: StrokeStyle(lineWidth: 1, dash: node.dashed ? [3, 3] : []))
        )
    }
}
