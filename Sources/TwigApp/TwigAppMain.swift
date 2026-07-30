import AppKit
import SwiftUI
import TwigCore
import UserNotifications

@main
struct TwigAppMain: App {
    @State private var appState: AppState
    @State private var widgetController: WidgetWindowController?

    init() {
        // 未打包为 .app（swift build 直跑）时 UserNotifications 无 bundle 可用，跳过授权
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        // App 启动即装配：备份/崩溃补记/收件箱监视/快照 + 悬浮窗
        let state = AppState()
        let controller = WidgetWindowController()
        _appState = State(initialValue: state)
        _widgetController = State(initialValue: controller)
        state.start()
        controller.show(rootView: WidgetView(appState: state, controller: controller))
        // 纵向枝干方向时收起态更高，启动即校正窗口高度
        controller.resize(toHeight: CollapsedBarView.barHeight(for: state.branchDirection), animated: false)
    }

    var body: some Scene {
        Window("Twig", id: "main") {
            MainWindowView(appState: appState)
                .onAppear { NSApp.activate() }
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra("Twig", systemImage: "leaf") {
            Button("打开主窗口") { openMain() }
            Divider()
            Button("退出 Twig") { NSApp.terminate(nil) }
        }
    }

    @Environment(\.openWindow) private var openWindow

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }
}
