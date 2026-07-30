import SwiftUI
import TwigCore

struct MainWindowView: View {
    let appState: AppState
    @State private var selectedProject: Project?
    @State private var showingReports = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            ProjectListView(appState: appState, selection: $selectedProject)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            if let project = selectedProject {
                TimelineView(appState: appState, project: project)
            } else {
                Text("选择一个项目")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            TaskDetailView()
        }
        .frame(minWidth: 860, minHeight: 540)
        .toolbar {
            ToolbarItemGroup {
                Button { showingReports.toggle() } label: {
                    Label("报表", systemImage: "chart.bar")
                }
                Button { showingSettings.toggle() } label: {
                    Label("设置", systemImage: "gear")
                }
            }
        }
        .sheet(isPresented: $showingReports) {
            ReportsView(appState: appState)
                .frame(minWidth: 560, minHeight: 420)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(appState: appState)
                .frame(width: 480, height: 480)
        }
    }
}
