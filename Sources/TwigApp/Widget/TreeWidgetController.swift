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
        // 悬停 HUD 的光标来源：TreeCanvasView 每帧轮询（非激活面板收不到 onHover）
        appState.widgetMouseProvider = { [weak window] in window?.mouseLocationInContent() }
        window.show(rootView: WidgetView(appState: appState, controller: self))
        applyLayout(animated: false)
    }

    /// widgetMode / 树包围盒 / 出土方向变化后重算窗口尺寸
    func applyLayout(animated: Bool = true) {
        switch appState.widgetMode {
        case .folded:
            let height = CollapsedBarView.barHeight(for: appState.pullDirection)
            window.resize(toWidth: 560, height: height, animated: animated)
        case .tree:
            window.resizeToFit(content: fittedContentSize(), animated: animated)
        }
    }

    /// 内容区 = 节点包围盒 + 内边距。
    /// 高度上限"屏幕 60%"（原 1/3 太矮：纵向链条两三层就超 440，深层节点被窗底裁切）；
    /// 下限默认画板（760×440）——笔记本屏的上限比默认画板还小，
    /// 直接封顶会裁切默认布局，所以默认尺寸内不设限，超出默认后封顶才生效
    private func fittedContentSize() -> CGSize {
        let bounds = appState.reportedTreeBounds
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1512, height: 982)
        let maxW = max(760, screen.width / 3)
        let maxH = max(440, screen.height * 0.6)
        return CGSize(
            // 宽度下限 680：两项目横排（minX+120+260 + 节点半宽75 + 卫星90 + 边距）
            width: min(max(680, bounds.width + 48), maxW),
            height: min(max(360, bounds.height + 48), maxH)
        )
    }
}
