import AppKit
import SwiftUI

@MainActor
@Observable
final class WidgetWindowController {
    private var panel: NSPanel?

    /// 内容区尺寸（树画板）：默认 760×440，TreeWidgetController 按节点包围盒调整。
    /// 设为可观察：WidgetView 的 treeSize 读它，扩窗后画布跟着重排
    var contentSize: CGSize = CGSize(width: 760, height: 440)

    func show<Content: View>(rootView: Content) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 544),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("TwigWidget")
        panel.contentView = NSHostingView(rootView: rootView)
        ensureVisible(panel)
        panel.orderFront(nil)
        self.panel = panel
    }

    /// 树画板态：窗口 = 横条(64) + 内容区 + 边距，宽度至少 560（横条宽度）
    func resizeToFit(content: CGSize, animated: Bool = true) {
        contentSize = content
        let w = max(560, content.width + 40)
        let h = 64 + (content.height > 0 ? content.height + 40 : 0)
        resize(toWidth: w, height: h, animated: animated)
    }

    /// 顶边不动、左边不动，向右向下扩/收
    func resize(toWidth width: CGFloat, height: CGFloat, animated: Bool = true) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// 被拖出屏幕则回到主屏右上角
    private func ensureVisible(_ panel: NSPanel) {
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !visible, let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - panel.frame.width - 40,
                y: screen.visibleFrame.maxY - panel.frame.height - 40
            ))
        }
    }
}
