import SwiftUI
import TwigCore

struct ProjectListView: View {
    let appState: AppState
    @Binding var selection: Project?
    @State private var newProjectName = ""

    var body: some View {
        List(appState.taskStore.allProjects(), id: \.persistentModelID, selection: $selection) { project in
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: project.colorHint) ?? .gray)
                    .frame(width: 10, height: 10)
                Text(project.name)
                Spacer()
                if project.repoPath == nil {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(.tertiary)
                        .help("未绑定 git 仓库")
                }
            }
            .tag(project)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("新项目名", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    guard !newProjectName.isEmpty else { return }
                    let p = appState.taskStore.addProject(name: newProjectName, colorHint: "#D97757")
                    newProjectName = ""
                    selection = p
                    appState.exportSnapshot()
                }
            }
            .padding(10)
        }
    }
}
