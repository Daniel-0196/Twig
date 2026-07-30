import SwiftUI
import TwigCore

struct WidgetView: View {
    let appState: AppState
    var controller: WidgetWindowController

    /// 收起态横条高度（含方向感知：纵向方向更高）
    private var barHeight: CGFloat {
        CollapsedBarView.barHeight(for: appState.branchTuning.direction)
    }

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                CollapsedBarView(appState: appState)
                switch appState.widgetState {
                case .collapsed:
                    EmptyView()
                case .peeked:
                    PeekListView(appState: appState)
                        .onHover { inside in
                            if !inside { appState.widgetState = .collapsed }
                        }
                case .expanded:
                    BranchView(appState: appState)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                // 兜底：指针离开整个悬浮窗区域（不经过清单）也要收回 peek
                if !inside, appState.widgetState == .peeked {
                    appState.widgetState = .collapsed
                }
            }
            .onAppear { appState.timerStore.tick() }
            .onChange(of: context.date) { appState.timerStore.tick() }
            .onChange(of: appState.branchTuning.direction) { _, _ in
                // 方向切换会改变收起态高度（纵向更高）
                if appState.widgetState == .collapsed {
                    controller.resize(toHeight: barHeight)
                }
            }
            .onChange(of: appState.widgetState) { _, state in
                switch state {
                case .collapsed: controller.resize(toHeight: barHeight)
                case .peeked: controller.resize(toHeight: barHeight + 220)
                case .expanded:
                    controller.resize(toHeight: barHeight + appState.branchContentSize.height)
                }
            }
            .onChange(of: appState.branchContentSize) { _, size in
                if appState.widgetState == .expanded {
                    controller.resize(toHeight: barHeight + size.height)
                }
            }
        }
    }
}
