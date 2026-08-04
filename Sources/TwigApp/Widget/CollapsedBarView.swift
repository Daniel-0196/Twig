import SwiftUI
import TwigCore

/// 紧凑横条：当前任务 + 计时 + 折叠钮；折叠态在末梢画向外延展的虚线（朝向跟随出土方向）。
/// 每个有未完成目标的项目一条虚线，末端一个项目色空心小圆。
/// 今日浮层（PeekListView）由 WidgetView 在树根层 overlay 渲染，本视图只上报悬停进出
struct CollapsedBarView: View {
    let appState: AppState
    /// 悬停进出回调（与浮层共享 WidgetView 的票号协调，跨过横条→浮层间隙不闪收）
    var onPeekHover: (Bool) -> Void = { _ in }

    /// 折叠态总高：纵向出土方向时虚线在横条上/下方，需要更高
    static func barHeight(for direction: PullDirection) -> CGFloat {
        switch direction {
        case .up, .down: return 112
        case .left, .right: return 64
        }
    }

    /// 有未完成目标的项目，每个项目一个末梢把柄
    private var branchColors: [String] {
        appState.taskStore.allProjects()
            .filter { $0.goals.contains { !$0.isDone } }
            .map(\.colorHint)
    }

    var body: some View {
        if appState.widgetMode == .folded {
            foldedBody
        } else {
            bar
        }
    }

    /// 折叠态：横条 + 方向化虚线末梢
    private var foldedBody: some View {
        let dashed = DashedExtensionView(direction: appState.pullDirection,
                                         handles: branchColors)
        return Group {
            switch appState.pullDirection {
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
        .frame(width: 560, height: Self.barHeight(for: appState.pullDirection))
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
            } else if case .idle = appState.engineState {
                // idle：对当前任务（第一个未完成任务）起番茄
                Button {
                    if let task = appState.taskStore.firstIncompleteTask() {
                        appState.timerStore.start(task: task, mode: .pomodoro)
                    }
                } label: {
                    Text("▶ 开始")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#D97757") ?? .orange)
                }
                .buttonStyle(.plain)
                .disabled(appState.taskStore.firstIncompleteTask() == nil)
                .help("对当前任务起番茄")
            } else {
                Text(timerText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(hex: "#D97757") ?? .orange)
            }
            // 折叠钮：▾ 收成横条 / ▸ 展开树画板
            Button {
                appState.widgetMode = appState.widgetMode == .tree ? .folded : .tree
            } label: {
                Image(systemName: appState.widgetMode == .tree ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(appState.widgetMode == .tree ? "折叠成横条" : "展开树画板")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 380)
        // 半透明白底垫在 material 上：透深色桌面时仍是浅色玻璃（对齐原型/节点卡）
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        )
        .onHover { onPeekHover($0) }
    }

    private var activeColorHex: String {
        if let hex = appState.timerStore.activeTask?.goal?.project?.colorHint { return hex }
        // idle：色点跟随"当前任务"所属项目（原型行为）
        if case .idle = appState.engineState {
            return appState.taskStore.firstIncompleteTask()?.goal?.project?.colorHint ?? "#D97757"
        }
        return "#D97757"
    }

    private var timerText: String {
        switch appState.engineState {
        case .idle: return "▶ 开始"
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

/// 横条末梢的虚线外延，朝向跟随出土方向。
/// 每个项目一条虚线，末端一个项目色空心小圆；无项目时退化为两条装饰虚线
struct DashedExtensionView: View {
    let direction: PullDirection
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
                    // 末梢空心小圆：项目色描边 + 半透明填充，约 10pt
                    let circle = Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
                    ctx.fill(circle, with: .color(.white.opacity(0.25)))
                    ctx.stroke(circle, with: .color(color.opacity(0.85)), lineWidth: 1.5)
                }
            }
        }
    }
}
