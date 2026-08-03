import SwiftData
import SwiftUI
import TwigCore

/// 任务详情（点叶子弹出）：番茄挂任务级
struct TaskLeafPopover: View {
    let appState: AppState
    /// 节点帧（画布坐标系）：弹卡定位到所属节点的叶子排下方
    var positions: [PersistentIdentifier: CGRect] = [:]

    var body: some View {
        if let (task, goal) = appState.leafTask {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.title).font(.system(size: 13, weight: .semibold, design: .serif))
                    Spacer()
                    Button { appState.leafTask = nil } label: {
                        Text("✕").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
                Text("\(goal.title) · \(goal.project?.name ?? "") · \(task.estimateMin.map { "约\($0)分钟" } ?? "未定")")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    leafAction("▶", color: Color(red: 0.85, green: 0.47, blue: 0.34), help: "开始番茄") {
                        appState.timerStore.start(task: task, mode: .pomodoro)
                        appState.leafTask = nil
                    }
                    leafAction("✓", color: Color(red: 0.49, green: 0.61, blue: 0.46), help: "完成") {
                        appState.taskStore.toggleTask(task)
                        appState.leafTask = nil
                        appState.exportSnapshot()
                    }
                    leafAction("🗑", color: .secondary, help: "删除任务") {
                        // 必须 delete 模型本身：只从 goal.tasks 摘掉会留下孤儿行，
                        // 继续出现在 TaskStore.incompleteTasks()/今日任务/Peek/报表里
                        appState.container.mainContext.delete(task)
                        try? appState.container.mainContext.save()
                        appState.leafTask = nil
                        appState.exportSnapshot()
                    }
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(.white.opacity(0.82))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 0.91, green: 0.90, blue: 0.86).opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            .position(popoverPos(for: goal))
        }
    }

    /// 定位：叶子排在 frame.maxY + 18，弹卡中心再往下让出半高（≈60）
    private func popoverPos(for goal: Goal) -> CGPoint {
        guard let frame = positions[goal.persistentModelID] else {
            return CGPoint(x: 120, y: 120)
        }
        return CGPoint(x: frame.midX, y: frame.maxY + 100)
    }

    private func leafAction(_ label: String, color: Color, help: String,
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
}
