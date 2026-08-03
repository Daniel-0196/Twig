import SwiftUI
import TwigCore

/// 悬浮窗主体：默认节点树画板，可折叠成横条（两态：tree / folded）
struct WidgetView: View {
    let appState: AppState
    var controller: TreeWidgetController

    var body: some View {
        // 模块内有同名 Main/TimelineView，必须全限定
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                CollapsedBarView(appState: appState)   // 头部横条（当前任务+番茄+折叠钮）
                if appState.widgetMode == .tree {
                    TreeCanvasView(appState: appState, size: controller.contentSize)
                }
            }
            .onAppear { appState.timerStore.tick() }
            .onChange(of: context.date) { appState.timerStore.tick() }
            .onChange(of: appState.widgetMode) { _, _ in controller.applyLayout() }
            .onChange(of: appState.pullDirection) { _, _ in controller.applyLayout() }
            .onChange(of: appState.reportedTreeBounds) { _, _ in
                // 节点包围盒变化 → 树画板态按需扩/收窗
                if appState.widgetMode == .tree { controller.applyLayout() }
            }
        }
    }
}
