import AppKit
import SwiftUI

@MainActor
final class WidgetWindowController {
    private var panel: NSPanel?

    func show<Content: View>(rootView: Content) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 64),
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

    /// 状态切换时改尺寸（展开枝干时变高变宽）。宽度默认 560（380 横条 + 180 枝干留白），
    /// 展开态按枝干内容宽度放大，避免超宽裁切
    func resize(toHeight height: CGFloat, animated: Bool = true) {
        resize(toWidth: 560, height: height, animated: animated)
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
