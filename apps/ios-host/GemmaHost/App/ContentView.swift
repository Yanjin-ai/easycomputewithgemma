import SwiftUI
import UserNotifications

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: AppTab = .newTask
    @State private var selectedTaskId: String?
    @State private var notificationDelegate = NotificationDelegate()

    private var selectedTaskDestination: Binding<SelectedTaskDestination?> {
        Binding(
            get: {
                selectedTaskId.map { SelectedTaskDestination(taskId: $0) }
            },
            set: { destination in
                selectedTaskId = destination?.taskId
            }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TaskInputView(onTaskSubmitted: { submittedTaskId in
                hideKeyboard()
                selectedTaskId = submittedTaskId
                withAnimation { selectedTab = .tasks }
            })
                .tabItem {
                    Label("New Task", systemImage: "square.and.pencil")
                }
                .tag(AppTab.newTask)

            NavigationStack {
                TaskListView()
                    .navigationDestination(item: selectedTaskDestination) { destination in
                        TaskDetailView(taskId: destination.taskId)
                    }
            }
            .tabItem {
                Label("Tasks", systemImage: "list.bullet")
            }
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
        .onAppear {
            notificationDelegate.onTaskTapped = { taskId in
                selectedTab = .tasks
                selectedTaskId = taskId
            }
            UNUserNotificationCenter.current().delegate = notificationDelegate
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

private struct SelectedTaskDestination: Hashable, Identifiable {
    let taskId: String

    var id: String {
        taskId
    }
}
