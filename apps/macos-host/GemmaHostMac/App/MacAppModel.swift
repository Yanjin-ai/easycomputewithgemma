import Foundation
import SwiftUI

@MainActor
final class MacAppModel: ObservableObject {
    @Published var deviceId: String?
    @Published var apiKey: String?
    @Published var tasks: [Task] = []
    @Published var registrationError: String?
    @Published var listError: String?
    @Published var isLoadingTasks = false

    let client: ControlPlaneClient
    let heartbeatService: HeartbeatService

    private let keychain: KeychainHelper
    private var refreshTimer: Timer?
    private var didBootstrap = false

    init(
        client: ControlPlaneClient? = nil,
        keychain: KeychainHelper = .shared
    ) {
        self.keychain = keychain
        let resolvedClient = client ?? ControlPlaneClient()
        self.client = resolvedClient
        self.heartbeatService = HeartbeatService(client: resolvedClient)

        deviceId = keychain.string(forKey: "mac_device_id")
        apiKey = keychain.string(forKey: "mac_api_key")
        resolvedClient.updateApiKeyProvider { [weak self] in
            self?.apiKey
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        if let deviceId {
            heartbeatService.start(deviceId: deviceId)
            startRefreshTimer()
            await refreshTasks()
            return
        }

        do {
            let response = try await client.registerDevice()
            try keychain.set(response.device.deviceId, forKey: "mac_device_id")
            if let apiKey = response.apiKey {
                try keychain.set(apiKey, forKey: "mac_api_key")
            }
            deviceId = response.device.deviceId
            apiKey = response.apiKey
            registrationError = nil
            heartbeatService.start(deviceId: response.device.deviceId)
            startRefreshTimer()
            await refreshTasks()
        } catch {
            registrationError = error.localizedDescription
        }
    }

    func refreshTasks() async {
        isLoadingTasks = true
        defer { isLoadingTasks = false }
        do {
            tasks = try await client.listTasks().tasks
            listError = nil
        } catch {
            listError = error.localizedDescription
        }
    }

    func submitQuickTask(rawInput: String) async throws {
        let trimmedInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        let draft = TaskDraft(
            intent: trimmedInput,
            goal: ["description": .string(trimmedInput)],
            requiredTools: [],
            requiredCapabilities: [],
            complexityHint: "light",
            permissionLevel: "private_lan",
            rawInput: trimmedInput
        )
        _ = try await client.submitTask(draft)
        await refreshTasks()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                await self?.refreshTasks()
            }
        }
    }
}
