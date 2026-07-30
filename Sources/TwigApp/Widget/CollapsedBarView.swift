import SwiftUI
import TwigCore

/// 紧凑横条：当前任务 + 计时 + 进度；末梢画向外延展的虚线（方向跟随枝干方向）
struct CollapsedBarView: View {
    let appState: AppState

    /// 收起态总高：纵向方向时虚线在横条上/下方，需要更高
    static func barHeight(for direction: BranchDirection) -> CGFloat {
        direction.isVertical ? 112 : 64
    }

    var body: some View {
        let dashed = DashedExtensionView(direction: appState.branchTuning.direction)
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
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { appState.widgetState = .peeked }
        }
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
            Text(timerText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color(hex: "#D97757") ?? .orange)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        )
    }

    private var activeColorHex: String {
        appState.timerStore.activeTask?.goal?.project?.colorHint ?? "#D97757"
    }

    private var timerText: String {
        switch appState.timerStore.engine.state {
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

/// 横条末梢的虚线外延，方向跟随枝干方向
struct DashedExtensionView: View {
    let direction: BranchDirection

    var body: some View {
        Canvas { ctx, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let start: CGPoint = switch direction {
            case .right: CGPoint(x: 8, y: mid.y)
            case .left: CGPoint(x: size.width - 8, y: mid.y)
            case .down, .up: mid
            }
            let ends: [CGPoint] = switch direction {
            case .right: [CGPoint(x: size.width - 12, y: mid.y - 24), CGPoint(x: size.width - 12, y: mid.y + 24)]
            case .left: [CGPoint(x: 12, y: mid.y - 24), CGPoint(x: 12, y: mid.y + 24)]
            case .down: [CGPoint(x: mid.x - 60, y: size.height - 6), CGPoint(x: mid.x + 60, y: size.height - 6)]
            case .up: [CGPoint(x: mid.x - 60, y: 6), CGPoint(x: mid.x + 60, y: 6)]
            }
            for end in ends {
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end,
                              control1: CGPoint(x: (start.x + end.x) / 2, y: start.y),
                              control2: CGPoint(x: (start.x + end.x) / 2, y: end.y))
                ctx.stroke(path, with: .color(.primary.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
            }
        }
    }
}
