import SwiftUI
import TwigCore

/// 悬停滑出：今日任务清单，可直接勾选
struct PeekListView: View {
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(appState.taskStore.tasksForToday(on: Date()).prefix(6), id: \.persistentModelID) { task in
                HStack(spacing: 8) {
                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color(hex: task.goal?.project?.colorHint ?? "#D97757") ?? .orange)
                    Text(task.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.taskStore.toggleTask(task)
                    appState.exportSnapshot()
                }
            }
            HStack {
                Spacer()
                Button("展开枝干") { appState.widgetState = .expanded }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.5), lineWidth: 1))
    }
}
