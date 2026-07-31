import SwiftUI
import TwigCore

/// 紧凑横条：当前任务 + 计时 + 进度；末梢画向外延展的虚线（方向跟随枝干方向）。
/// 每个有未完成目标的项目一条虚线，末端一个项目色空心小圆——悬停虚线/小圆区域即展开枝干
struct CollapsedBarView: View {
    let appState: AppState

    /// 收起态总高：纵向方向时虚线在横条上/下方，需要更高
    static func barHeight(for direction: BranchDirection) -> CGFloat {
        direction.isVertical ? 112 : 64
    }

    /// 有未完成目标的项目（与枝干布局一致），每个项目一个末梢把柄
    private var branchColors: [String] {
        appState.taskStore.allProjects()
            .filter { $0.goals.contains { !$0.isDone } }
            .map(\.colorHint)
    }

    var body: some View {
        let dashed = DashedExtensionView(direction: appState.branchTuning.direction,
                                         handles: branchColors)
            .contentShape(Rectangle())
            .onHover { hovering in
                // 悬停虚线/末梢圆区域 → 展开枝干（画板态）；展开后经过该区域不改变状态
                if hovering, appState.widgetState != .expanded {
                    appState.widgetState = .expanded
                }
            }
        Group {
            switch appState.branchTuning.direction {
            case .right:
                HStack(spacing: 0) { bar; dashed.frame(width: 160) }
            case .left:
                HStack(spacing: 0) { dashed.frame(width: 160); bar }
            case .down:
                VStack(spacing: 0) { bar; dashed.frame(height: 48) }
            case .up:
                VStack(spacing: 0) { dashed.frame(height: 48); bar }
            }
        }
        .frame(width: 560, height: Self.barHeight(for: appState.branchTuning.direction))
    }

    /// 横条本体（内容不随方向变化）
    private var bar: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: activeColorHex) ?? .orange)
                .frame(width: 10, height: 10)
            Text(appState.currentFocusTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            if appState.pendingCompletionCheck {
                // 番茄结束后的"任务完成了吗？"：横条上直接确认
                HStack(spacing: 8) {
                    Button("✓ 完成") {
                        appState.timerStore.dismissCompletionCheck(markTaskDone: true)
                        appState.exportSnapshot()
                    }
                    Button("↻ 继续") {
                        appState.timerStore.dismissCompletionCheck(markTaskDone: false)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text(timerText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: "#D97757") ?? .orange)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            // 悬停横条 → 今日清单；仅收起态触发，展开态指针经过横条不掉回 peek
            if hovering, appState.widgetState == .collapsed {
                appState.widgetState = .peeked
            }
        }
    }

    private var activeColorHex: String {
        appState.timerStore.activeTask?.goal?.project?.colorHint ?? "#D97757"
    }

    private var timerText: String {
        switch appState.engineState {
        case .idle: return "开始"
        case .focusing(let startedAt, let plannedEnd, _):
            let seconds: Int
            if let plannedEnd {
                seconds = max(0, Int(plannedEnd.timeIntervalSince(Date())))
            } else {
                seconds = Int(Date().timeIntervalSince(startedAt))
            }
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .onBreak(_, let endsAt, _):
            let seconds = max(0, Int(endsAt.timeIntervalSinceNow))
            return String(format: "休 %d:%02d", seconds / 60, seconds % 60)
        }
    }
}

/// 横条末梢的虚线外延，方向跟随枝干方向。
/// 每个项目一条虚线，末端一个项目色空心小圆（悬停把柄）；无项目时退化为两条装饰虚线
struct DashedExtensionView: View {
    let direction: BranchDirection
    /// 项目色 hex 列表（有未完成目标的项目）
    let handles: [String]

    var body: some View {
        Canvas { ctx, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let start: CGPoint = switch direction {
            case .right: CGPoint(x: 8, y: mid.y)
            case .left: CGPoint(x: size.width - 8, y: mid.y)
            case .down, .up: mid
            }
            let count = max(handles.count, 2)
            // 末梢沿交叉轴居中铺开（纵向方向沿 x，横向方向沿 y）
            let span: CGFloat = switch direction {
            case .right, .left: min(52, CGFloat(count - 1) * 26)
            case .down, .up: min(160, CGFloat(count - 1) * 56)
            }
            for i in 0..<count {
                let t = count > 1 ? (CGFloat(i) / CGFloat(count - 1) - 0.5) : 0
                let end: CGPoint = switch direction {
                case .right: CGPoint(x: size.width - 14, y: mid.y + t * span)
                case .left: CGPoint(x: 14, y: mid.y + t * span)
                case .down: CGPoint(x: mid.x + t * span, y: size.height - 8)
                case .up: CGPoint(x: mid.x + t * span, y: 8)
                }
                let hex = i < handles.count ? handles[i] : nil
                let lineColor = hex.flatMap { Color(hex: $0)?.opacity(0.55) } ?? .primary.opacity(0.3)
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end,
                              control1: CGPoint(x: (start.x + end.x) / 2, y: start.y),
                              control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                ctx.stroke(path, with: .color(lineColor),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
                if let hex, let color = Color(hex: hex) {
                    // 末梢空心小圆：项目色描边 + 半透明填充，约 10pt，作为可悬停的把柄
                    let circle = Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
                    ctx.fill(circle, with: .color(.white.opacity(0.25)))
                    ctx.stroke(circle, with: .color(color.opacity(0.85)), lineWidth: 1.5)
                }
            }
        }
    }
}
