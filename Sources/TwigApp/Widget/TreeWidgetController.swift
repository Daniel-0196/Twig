import AppKit
import SwiftUI

/// 悬浮窗装配与尺寸策略：
/// 树画板态窗口 = 横条 + 树内容包围盒 + 边距（按需扩缩，上限屏幕 1/3，下限默认画板尺寸）；
/// 折叠态窗口 = 横条 + 虚线末梢（560 宽，纵向方向更高）
@MainActor
final class TreeWidgetController {
    let appState: AppState
    let window: WidgetWindowController

    init(appState: AppState) {
        self.appState = appState
        self.window = WidgetWindowController()
    }

    /// 当前树画板内容区尺寸（WidgetView 的 treeSize 读这里）
    var contentSize: CGSize { window.contentSize }

    /// 装配并显示悬浮窗；启动即展开树画板（不再"悬停才展开"）
    func start() {
        window.show(rootView: WidgetView(appState: appState, controller: self))
        applyLayout(animated: false)
    }

    /// widgetMode / 树包围盒 / 出土方向变化后重算窗口尺寸
    func applyLayout(animated: Bool = true) {
        switch appState.widgetMode {
        case .folded:
            var height = CollapsedBarView.barHeight(for: appState.pullDirection)
            if appState.peekListVisible {
                // 今日浮层滑出：窗口向下扩高容纳（顶边不动）
                let rows = min(PeekListView.maxRows,
                               appState.taskStore.tasksForToday(on: Date()).count)
                height += PeekListView.height(forRowCount: rows) + 6
            }
            window.resize(toWidth: 560, height: height, animated: animated)
        case .tree:
            // 树画板态浮层滑出也要扩窗：浮层在窗口外收不到 hover-exit，会一直卡着不关
            var content = fittedContentSize()
            if appState.peekListVisible {
                let rows = min(PeekListView.maxRows,
                               appState.taskStore.tasksForToday(on: Date()).count)
                content.height += PeekListView.height(forRowCount: rows) + 12
            }
            window.resizeToFit(content: content, animated: animated)
        }
    }

    /// 内容区 = 节点包围盒 + 内边距。
    /// 上限"屏幕 1/3"但不低于默认画板（760×440）——笔记本屏的 1/3 比默认画板还小，
    /// 直接封顶会裁切默认布局，所以默认尺寸内不设限，超出默认后 1/3 封顶才生效
    private func fittedContentSize() -> CGSize {
        let bounds = appState.reportedTreeBounds
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1512, height: 982)
        let maxW = max(760, screen.width / 3)
        let maxH = max(440, screen.height / 3)
        return CGSize(
            width: min(max(560, bounds.width + 48), maxW),
            height: min(max(360, bounds.height + 48), maxH)
        )
    }
}
