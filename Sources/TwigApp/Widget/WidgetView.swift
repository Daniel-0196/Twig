import SwiftUI
import TwigCore

/// 悬浮窗主体：默认节点树画板，可折叠成横条（两态：tree / folded）。
/// 整个悬浮窗强制浅色（深色桌面下 .ultraThinMaterial 会渲染成深灰玻璃，设计是 Claude 浅色）
struct WidgetView: View {
    let appState: AppState
    var controller: TreeWidgetController

    /// 今日浮层显隐协调票号：横条与浮层共用，每次进出 +1，延迟收回只认最新票
    @State private var peekTicket = 0

    var body: some View {
        // 模块内有同名 Main/TimelineView，必须全限定
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    CollapsedBarView(appState: appState, onPeekHover: peekHover)   // 头部横条
                    if appState.widgetMode == .tree {
                        TreeCanvasView(appState: appState, size: controller.contentSize)
                    }
                }
                if appState.peekListVisible {
                    // 今日浮层：树画板上方 overlay，只出现在横条正下方（z 序压过节点卡）
                    PeekListView(appState: appState, onHoverChange: peekHover)
                        .padding(.leading, 20)
                        .offset(y: peekTopOffset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .preferredColorScheme(.light)
            .animation(.easeInOut(duration: 0.18), value: appState.peekListVisible)
            .onAppear { appState.timerStore.tick() }
            .onChange(of: context.date) {
                appState.timerStore.tick()
                // 浮层防卡死兜底：非激活面板的 hover-exit 事件可能丢失，每秒核对一次。
                // 保活区域 = 横条 + 浮层本体（原型：离开横条/浮层即收）；
                // 不能用"光标在整个窗口内"——树画板态窗口很大，浮层会常开挡住画布
                if appState.peekListVisible {
                    let rows = min(PeekListView.maxRows,
                                   appState.taskStore.tasksForToday(on: Date()).count)
                    let band = peekTopOffset + PeekListView.height(forRowCount: rows) + 12
                    if !controller.window.cursorInTopBand(width: 400, height: band) {
                        appState.peekListVisible = false
                    }
                }
            }
            .onChange(of: appState.widgetMode) { _, _ in controller.applyLayout() }
            .onChange(of: appState.pullDirection) { _, _ in controller.applyLayout() }
            .onChange(of: appState.peekListVisible) { _, visible in
                // 展开瞬间立即扩窗（浮层区域须在窗口内才收得到悬停事件）；收回时动画缩回
                controller.applyLayout(animated: !visible)
            }
            .onChange(of: appState.reportedTreeBounds) { _, _ in
                // 节点包围盒变化 → 树画板态按需扩/收窗
                if appState.widgetMode == .tree { controller.applyLayout() }
            }
        }
    }

    /// 浮层顶缘：树画板态贴横条（64）下缘；折叠态在整个横条（含虚线末梢）之下
    private var peekTopOffset: CGFloat {
        switch appState.widgetMode {
        case .tree: return 64 + 6
        case .folded: return CollapsedBarView.barHeight(for: appState.pullDirection) + 6
        }
    }

    /// 悬停进出（横条与浮层共用）：进入即开，离开延迟 180ms 收回——
    /// 期间若进入另一方（票号失效）则保持展开
    private func peekHover(_ inside: Bool) {
        peekTicket &+= 1
        let ticket = peekTicket
        if inside {
            appState.peekListVisible = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                if ticket == peekTicket { appState.peekListVisible = false }
            }
        }
    }
}
