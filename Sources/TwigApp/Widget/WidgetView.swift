import SwiftUI
import TwigCore

struct WidgetView: View {
    let appState: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                CollapsedBarView(appState: appState)
                if appState.widgetState == .peeked {
                    Text("今日任务清单（Task 10 实现）")
                        .font(.caption)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { appState.widgetState = .collapsed }
                }
            }
            .onAppear { appState.timerStore.tick() }
            .onChange(of: context.date) { appState.timerStore.tick() }
        }
    }
}
