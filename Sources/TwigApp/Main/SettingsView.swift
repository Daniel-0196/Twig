import SwiftUI
import ServiceManagement
import TwigCore

struct SettingsView: View {
    let appState: AppState
    @State private var config = TimerConfig.load()
    @State private var badLineCount = 0
    @State private var loginItem = false

    var body: some View {
        Form {
            Section("枝干") {
                Picker("出土方向", selection: Binding(
                    get: { appState.pullDirection },
                    set: { appState.pullDirection = $0 }
                )) {
                    Text("向下拽").tag(PullDirection.down)
                    Text("向上拽").tag(PullDirection.up)
                    Text("向左拽").tag(PullDirection.left)
                    Text("向右拽").tag(PullDirection.right)
                }
                Text("拖拽方向 = 出土方向；树朝反方向的土壤长")
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
    }
}
