import AppIntents
import SwiftUI
import UserNotifications

@main
struct GemmaHostApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var notificationRouter = NotificationRouter()
    @AppStorage(AppConfig.onboardingCompleteKey) private var onboardingComplete = false
    @AppStorage("app_shortcuts_parameters_updated") private var appShortcutsParametersUpdated = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(model)
                    .navigationDestination(item: $notificationRouter.selectedTaskDestination) { destination in
                        TaskDetailView(taskId: destination.taskId)
                    }
                    .fullScreenCover(isPresented: onboardingPresentation) {
                        OnboardingView {
                            onboardingComplete = true
                            _Concurrency.Task {
                                await model.bootstrap()
                            }
                        }
                        .environmentObject(model)
                    }
                    .onAppear {
                        notificationRouter.register()
                    }
                    .task {
                        if !appShortcutsParametersUpdated {
                            GemmaShortcutsProvider.updateAppShortcutParameters()
                            appShortcutsParametersUpdated = true
                        }
                        guard onboardingComplete else { return }
                        await model.bootstrap()
                    }
            }
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { !onboardingComplete },
            set: { isPresented in
                if !isPresented {
                    onboardingComplete = true
                }
            }
        )
    }
}

@MainActor
private final class NotificationRouter: ObservableObject {
    @Published var selectedTaskDestination: SelectedNotificationTask?

    private let notificationDelegate = NotificationDelegate()

    init() {
        notificationDelegate.onTaskTapped = { [weak self] taskId in
            self?.selectedTaskDestination = SelectedNotificationTask(taskId: taskId)
        }
        register()
    }

    func register() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
}

private struct SelectedNotificationTask: Hashable, Identifiable {
    let taskId: String

    var id: String {
        taskId
    }
}
