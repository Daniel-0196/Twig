import AppKit
import SwiftUI
import TwigCore
import UserNotifications

@main
struct TwigAppMain: App {
    @State private var appState: AppState
    @State private var treeController: TreeWidgetController?

    init() {
        // 未打包为 .app（swift build 直跑）时 UserNotifications 无 bundle 可用，跳过授权
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        // App 启动即装配：备份/崩溃补记/收件箱监视/快照 + 悬浮窗（启动默认展开树画板）
        let state = AppState()
        let controller = TreeWidgetController(appState: state)
        _appState = State(initialValue: state)
        _treeController = State(initialValue: controller)
        state.start()
        controller.start()
    }

    var body: some Scene {
        Window("Twig", id: "main") {
            MainWindowView(appState: appState)
                .onAppear { NSApp.activate() }
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            // 读 AppState 的 @Observable 镜像（engineState），而非不可观察的 engine.state
            switch appState.engineState {
            case .idle:
                Button("开始番茄钟") { appState.timerStore.start(task: nil, mode: .pomodoro) }
                Button("开始正计时") { appState.timerStore.start(task: nil, mode: .stopwatch) }
            case .focusing:
                Button("提前完成") { appState.timerStore.finishFocus() }
                Button("停止并保留") { appState.timerStore.stop(discard: false) }
                Button("停止并丢弃") { appState.timerStore.stop(discard: true) }
            case .onBreak:
                Button("结束休息") { appState.timerStore.endBreak() }
            }
            Divider()
            Menu("出土方向") {
                ForEach(PullDirection.allCases, id: \.self) { d in
                    Button {
                        appState.pullDirection = d
                    } label: {
                        if appState.pullDirection == d {
                            Label(directionLabel(d), systemImage: "checkmark")
                        } else {
                            Text(directionLabel(d))
                        }
                    }
                }
            }
            Button(appState.widgetMode == .tree ? "折叠悬浮窗" : "展开悬浮窗") {
                appState.widgetMode = appState.widgetMode == .tree ? .folded : .tree
            }
            Button("重置节点位置") {
                for p in appState.taskStore.allProjects() { appState.resetTree(p) }
            }
            Divider()
            Button("打开主窗口") { openMain() }
            Divider()
            Button("退出 Twig") { NSApp.terminate(nil) }
        } label: {
            MenuBarIcon()
        }
    }

    @Environment(\.openWindow) private var openWindow

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func directionLabel(_ d: PullDirection) -> String {
        switch d {
        case .up: return "向上"
        case .down: return "向下"
        case .left: return "向左"
        case .right: return "向右"
        }
    }
}

/// 菜单栏模板图标：与 app icon 同母题（细线串三点），加载失败退回 SF Symbol
private struct MenuBarIcon: View {
    private let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "menubar-icon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    var body: some View {
        if let image {
            Image(nsImage: image)
        } else {
            Image(systemName: "leaf")
        }
    }
}
