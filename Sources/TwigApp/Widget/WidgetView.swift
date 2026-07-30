import SwiftUI
import TwigCore

struct WidgetView: View {
    let appState: AppState
    var controller: WidgetWindowController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 8) {
                CollapsedBarView(appState: appState)
                switch appState.widgetState {
                case .collapsed:
                    EmptyView()
                case .peeked:
                    PeekListView(appState: appState)
                        .onHover { inside in
                            if !inside { appState.widgetState = .collapsed }
                        }
                case .expanded:
                    BranchView(appState: appState)
                }
            }
            .onAppear { appState.timerStore.tick() }
            .onChange(of: context.date) { appState.timerStore.tick() }
            .onChange(of: appState.widgetState) { _, state in
                switch state {
                case .collapsed: controller.resize(toHeight: 64)
                case .peeked: controller.resize(toHeight: 64 + 220)
                case .expanded:
                    controller.resize(toHeight: 64 + appState.branchContentSize.height)
                }
            }
            .onChange(of: appState.branchContentSize) { _, size in
                if appState.widgetState == .expanded {
                    controller.resize(toHeight: 64 + size.height)
                }
            }
        }
    }
}
