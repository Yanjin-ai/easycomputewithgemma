import SwiftUI

struct ContentView: View {
    /// Task ID pushed from a notification tap (passed down from GemmaHostApp).
    var notificationTaskId: String?

    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .newTask
    @State private var navigationPath: [String] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            // ── New Task tab ──────────────────────────────────────────────
            TaskInputView(onTaskSubmitted: { _ in
                // Dismiss keyboard then switch to Tasks tab.
                // We do NOT push to detail here to avoid navigation conflicts.
                hideKeyboard()
                withAnimation { selectedTab = .tasks }
            })
            .tabItem { Label("New Task", systemImage: "square.and.pencil") }
            .tag(AppTab.newTask)

            // ── Tasks tab (single NavigationStack for the whole app) ──────
            NavigationStack(path: $navigationPath) {
                TaskListView()
                    .navigationDestination(for: String.self) { taskId in
                        TaskDetailView(taskId: taskId)
                    }
            }
            .tabItem { Label("Tasks", systemImage: "list.bullet") }
            .tag(AppTab.tasks)
        }
        .overlay(alignment: .top) {
            if let registrationError = model.registrationError {
                Text(registrationError)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.red, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        // Handle notification deep-link: switch to Tasks tab and push detail.
        .onChange(of: notificationTaskId) { taskId in
            guard let taskId else { return }
            selectedTab = .tasks
            navigationPath = [taskId]
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
}

enum AppTab {
    case newTask, tasks
}
