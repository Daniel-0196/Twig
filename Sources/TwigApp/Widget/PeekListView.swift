import SwiftUI
import TwigCore

/// 悬停横条滑出的今日任务清单（v1 PeekListView 的 v2 重制）：
/// 最多 6 条未完成任务，点击圆圈勾选，行尾 ▶ 对该任务起番茄，移开收回。
/// 视觉沿用 TaskLeafPopover 的玻璃卡片风格
struct PeekListView: View {
    let appState: AppState
    /// 悬停进出回调（与横条共享显隐协调，跨过横条→浮层间隙不收回）
    var onHoverChange: (Bool) -> Void = { _ in }

    static let maxRows = 6
    static let rowHeight: CGFloat = 30

    private var tasks: [TwigCore.Task] {
        Array(appState.taskStore.tasksForToday(on: Date()).prefix(Self.maxRows))
    }

    /// 浮层高度：折叠态窗口按行数扩高（空态也占一行）。
    /// 行高 30 + 行距 4，常数项 = 标题行 14 + 间距 4 + 上下内边距 20（宁可多留，窗口透明不可见）
    static func height(forRowCount rows: Int) -> CGFloat {
        CGFloat(max(rows, 1)) * (rowHeight + 4) + 38
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            if tasks.isEmpty {
                Text("今日无待办")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Self.rowHeight)
            } else {
                ForEach(tasks, id: \.persistentModelID) { task in
                    row(task)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 340, alignment: .leading)
        .background(.white.opacity(0.82))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .onHover { onHoverChange($0) }
    }

    private func row(_ task: TwigCore.Task) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.taskStore.toggleTask(task)
                appState.exportSnapshot()
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: task.goal?.project?.colorHint ?? "#D97757") ?? .orange)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("勾选完成")
            Text(task.title)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                appState.timerStore.start(task: task, mode: .pomodoro)
            } label: {
                Text("▶")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("对该任务起番茄")
        }
        .frame(height: Self.rowHeight)
    }
}
