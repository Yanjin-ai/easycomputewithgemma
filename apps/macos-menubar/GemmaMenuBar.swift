import AppKit
import SwiftUI

@main
struct GemmaMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: MenuBarModel?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = MenuBarModel()
        self.model = model
        self.statusBarController = StatusBarController(model: model)

        Task {
            await model.start()
        }
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published private(set) var tasks: [GemmaTask] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let keychain = KeychainHelper.shared
    private let apiKeyKey = "api_key"
    private let deviceIdKey = "device_id"
    private lazy var client = ControlPlaneClient { [weak self] in
        self?.apiKey
    }
    private var apiKey: String?
    private var deviceId: String?
    private var pollingTask: Task<Void, Never>?

    func start() async {
        deviceId = keychain.string(forKey: deviceIdKey)
        apiKey = keychain.string(forKey: apiKeyKey)

        if deviceId == nil {
            await registerDevice()
        }

        await refreshTasks()
        startPolling()
    }

    func refreshTasks() async {
        guard deviceId != nil else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let latestTasks = try await client.listTasks(limit: 10)
            tasks = latestTasks
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func taskDetails(taskId: String) async throws -> (GemmaTask, [TaskEvent]) {
        async let task = client.getTask(taskId: taskId)
        async let events = client.fetchEvents(taskId: taskId, limit: 5)
        return try await (task, events)
    }

    private func registerDevice() async {
        errorMessage = nil

        do {
            let response = try await client.registerDevice()
            try keychain.set(response.apiKey, forKey: apiKeyKey)
            try keychain.set(response.device.deviceId, forKey: deviceIdKey)
            apiKey = response.apiKey
            deviceId = response.device.deviceId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self?.refreshTasks()
            }
        }
    }
}
