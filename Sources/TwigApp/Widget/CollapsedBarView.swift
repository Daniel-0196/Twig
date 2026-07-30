import SwiftUI
import TwigCore

/// 紧凑横条：当前任务 + 计时 + 进度；右侧透明区画向外延展的虚线
struct CollapsedBarView: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 0) {
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

            // 向屏幕外延展的虚线（点击枝干区在 Task 10 接管）
            Canvas { ctx, size in
                let start = CGPoint(x: 8, y: size.height / 2)
                for offset in [-18.0, 16.0] {
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(
                        to: CGPoint(x: size.width - 20, y: size.height / 2 + offset * 2),
                        control1: CGPoint(x: 60, y: size.height / 2),
                        control2: CGPoint(x: 90, y: size.height / 2 + offset)
                    )
                    ctx.stroke(path, with: .color(.primary.opacity(0.3)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
                }
            }
            .frame(width: 160)
        }
        .frame(width: 560, height: 64)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { appState.widgetState = .peeked }
        }
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
