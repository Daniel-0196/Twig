import SwiftUI
import ServiceManagement
import TwigCore

struct SettingsView: View {
    let appState: AppState
    @State private var config = TimerConfig.load()
    @State private var badLineCount = 0
    @State private var loginItem = false
    @AppStorage("twig.branchDirection") private var branchDirection = BranchDirection.right.rawValue

    var body: some View {
        Form {
            Section("枝干") {
                Picker("延展方向", selection: $branchDirection) {
                    Text("向右").tag(BranchDirection.right.rawValue)
                    Text("向左").tag(BranchDirection.left.rawValue)
                    Text("向下").tag(BranchDirection.down.rawValue)
                    Text("向上").tag(BranchDirection.up.rawValue)
                }
                Text("悬浮窗贴在屏幕哪条边，就选相反方向")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("计时器") {
                Stepper("专注 \(config.focusMinutes) 分钟", value: $config.focusMinutes, in: 5...120, step: 5)
                Stepper("短休息 \(config.shortBreakMinutes) 分钟", value: $config.shortBreakMinutes, in: 1...30)
                Stepper("长休息 \(config.longBreakMinutes) 分钟", value: $config.longBreakMinutes, in: 5...60, step: 5)
                Stepper("每 \(config.pomodorosPerLongBreak) 个番茄后长休息", value: $config.pomodorosPerLongBreak, in: 2...8)
                Toggle("到点自动开始休息", isOn: $config.autoStartBreak)
                Toggle("提示音", isOn: $config.soundEnabled)
                Toggle("系统通知", isOn: $config.notificationsEnabled)
            }
            Section("系统") {
                Toggle("登录后自动启动（需以 Twig.app 形式运行）", isOn: $loginItem)
                    .onChange(of: loginItem) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch { loginItem = false }
                    }
            }
            Section("收件箱") {
                Text(badLineCount == 0 ? "没有导入失败的记录" : "有 \(badLineCount) 条导入失败，见 inbox.bad.jsonl")
                    .foregroundStyle(badLineCount == 0 ? Color.secondary : Color.orange)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            badLineCount = (try? String(contentsOf: TwigPaths.badLinesURL, encoding: .utf8))?
                .split(separator: "\n").count ?? 0
        }
        .onChange(of: config) { _, newValue in
            newValue.save()
            appState.timerStore.engine.config = newValue
        }
        .onChange(of: branchDirection) { _, newValue in
            // 同步到运行中的 AppState，悬浮窗即时换方向（@AppStorage 只保证重启后生效）
            if let direction = BranchDirection(rawValue: newValue) {
                appState.branchDirection = direction
            }
        }
    }
}
