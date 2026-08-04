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
        panel.isMovableByWindowBackground = false   // 背景拖动会吃掉节点拖拽：窗口只能拖横条
        // 悬浮窗永远浅色（深色桌面下材料/控件不能变深灰）
        panel.appearance = NSAppearance(named: .aqua)
        // 非激活面板也要收 mouse-moved 事件（SwiftUI onHover/tracking area 的前提；
        // 悬停 HUD 另由 TreeCanvasView 轮询 mouseLocationInContent 驱动，双保险）
        panel.acceptsMouseMovedEvents = true
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
        // 扩窗后若右/下边出屏则整体挪回屏内（顶边尽量不动）
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            if frame.maxX > vis.maxX { frame.origin.x = max(vis.minX, vis.maxX - frame.width) }
            if frame.minX < vis.minX { frame.origin.x = vis.minX }   // 左边出屏也拉回（拖动/autosave 恢复可能越界）
            if frame.minY < vis.minY { frame.origin.y = vis.minY }
        }
        panel.setFrame(frame, display: true, animate: animated)
    }

    /// 光标是否还在悬浮窗内（外扩 padding 容差）：今日浮层防卡死兜底用
    func cursorInside(padding: CGFloat = 12) -> Bool {
        guard let panel else { return false }
        return panel.frame.insetBy(dx: -padding, dy: -padding).contains(NSEvent.mouseLocation)
    }

    /// 光标在窗口内容坐标系（左上角原点，与 SwiftUI .global 一致）的位置；不在窗口内为 nil。
    /// NSPanel 非激活时 SwiftUI onHover 收不到事件，悬停 HUD 靠每帧轮询这个位置驱动
    func mouseLocationInContent() -> CGPoint? {
        guard let panel else { return nil }
        let screen = NSEvent.mouseLocation
        guard panel.frame.contains(screen) else { return nil }
        return CGPoint(x: screen.x - panel.frame.minX, y: panel.frame.maxY - screen.y)
    }

    /// 光标是否在窗口顶部条带（横条 + 今日浮层区域）内：浮层保活判定。
    /// 原兜底"光标在整个窗口内就不收"在树画板态会让浮层常开——窗口很大，
    /// 光标只是在画布上晃浮层就一直挡着画布；原型行为是离开横条/浮层即收
    func cursorInTopBand(width: CGFloat, height: CGFloat) -> Bool {
        guard let loc = mouseLocationInContent() else { return false }
        return loc.x <= width && loc.y <= height
    }

    /// 启动时把窗口拉回主屏可见区：完全出屏回右上角；部分出屏（拖到边缘/外接屏拔掉/
    /// autosave 恢复越界）逐边夹回可见区
    private func ensureVisible(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) })
                ?? NSScreen.main else { return }
        let vis = screen.visibleFrame
        var frame = panel.frame
        if !vis.intersects(frame) {
            frame.origin = NSPoint(x: vis.maxX - frame.width - 40, y: vis.maxY - frame.height - 40)
        }
        if frame.maxX > vis.maxX { frame.origin.x = max(vis.minX, vis.maxX - frame.width) }
        if frame.minX < vis.minX { frame.origin.x = vis.minX }
        if frame.maxY > vis.maxY { frame.origin.y = vis.maxY - frame.height }
        if frame.minY < vis.minY { frame.origin.y = vis.minY }
        if frame != panel.frame { panel.setFrame(frame, display: false) }
    }
}
