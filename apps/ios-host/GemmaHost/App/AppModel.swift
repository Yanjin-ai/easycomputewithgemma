import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceId: String?
    @Published var apiKey: String?
    @Published var registrationError: String?
    @Published var tasks: [Task] = []
    @Published var listError: String?
    @Published var isLoadingTasks = false
    @Published var modelManager: ModelManager

    let client: ControlPlaneClient
    var parser: any ParserRouterService
    let heartbeatService: HeartbeatService

    private let keychain: KeychainHelper
    private var isBootstrapping = false
    private var authFailedObserver: NSObjectProtocol?
    private var taskPollingTasks: [String: _Concurrency.Task<Void, Never>] = [:]

    init(
        client: ControlPlaneClient? = nil,
        parser: any ParserRouterService = StubParserRouterService(),
        modelManager: ModelManager? = nil,
        keychain: KeychainHelper = .shared
    ) {
        self.keychain = keychain
        self.parser = parser
        self.modelManager = modelManager ?? ModelManager()
        let resolvedClient = client ?? ControlPlaneClient()
        self.client = resolvedClient
        self.heartbeatService = HeartbeatService(client: resolvedClient)
        _ = NotificationService.shared

        deviceId = keychain.string(forKey: "device_id")
        apiKey = keychain.string(forKey: "api_key")
        resolvedClient.updateApiKeyProvider { [weak self] in
            self?.apiKey
        }
        resolvedClient.updateDeviceIdProvider { [weak self] in
            self?.deviceId
        }
        authFailedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("DeviceAuthFailed"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { await self?.bootstrap() }
        }
    }

    deinit {
        if let authFailedObserver {
            NotificationCenter.default.removeObserver(authFailedObserver)
        }
        for pollingTask in taskPollingTasks.values {
            pollingTask.cancel()
        }
    }

    var parserIsReady: Bool {
        if case .ready = modelManager.state {
            return true
        }

        return false
    }

    func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        if let deviceId {
            let isValid = await client.verifyDevice(deviceId: deviceId)
            if isValid {
                registrationError = nil
                heartbeatService.start(deviceId: deviceId)
                await bootstrapParser()
                await refreshTasks()
                return
            } else {
                resetRegistration()
            }
        }

        do {
            let response = try await client.registerDevice()
            try keychain.set(response.device.deviceId, forKey: "device_id")
            if let apiKey = response.apiKey {
                try keychain.set(apiKey, forKey: "api_key")
            }
            deviceId = response.device.deviceId
            apiKey = response.apiKey
            registrationError = nil
            heartbeatService.start(deviceId: response.device.deviceId)
            await bootstrapParser()
            await refreshTasks()
        } catch {
            registrationError = error.localizedDescription
        }
    }

    private func bootstrapParser() async {
        await modelManager.bootstrap()

        guard case .ready = modelManager.state else {
            parser = StubParserRouterService()
            return
        }

        loadOnDeviceParserIfReady()
    }

    func loadOnDeviceParserIfReady() {
        guard case .ready = modelManager.state else {
            parser = StubParserRouterService()
            return
        }

        let onDeviceParser = OnDeviceParserRouterService(modelManager: modelManager)
        do {
            try onDeviceParser.load()
            parser = onDeviceParser
        } catch {
            parser = StubParserRouterService()
        }
    }

    func refreshTasks() async {
        isLoadingTasks = true
        defer { isLoadingTasks = false }
        do {
            let existingSummaries = Dictionary(
                uniqueKeysWithValues: tasks.compactMap { task in
                    task.completionSummary.map { (task.taskId, $0) }
                }
            )
            let existingOutputSummaries = Dictionary(
                uniqueKeysWithValues: tasks.compactMap { task in
                    task.outputSummary.map { (task.taskId, $0) }
                }
            )
            tasks = try await client.listTasks().tasks.map { task in
                var mergedTask = task
                if mergedTask.outputSummary == nil,
                   let existingOutputSummary = existingOutputSummaries[task.taskId] {
                    mergedTask.outputSummary = existingOutputSummary
                }
                guard mergedTask.completionSummary == nil,
                      let existingSummary = existingSummaries[task.taskId] else {
                    return mergedTask
                }
                return mergedTask.withCompletionSummary(existingSummary)
            }
            listError = nil
        } catch {
            listError = error.localizedDescription
        }
    }

    func submitTask(text: String) async throws -> Task {
        let draft = await parser.parse(text: text)
        let submittedTask = try await client.submitTask(draft)
        upsertTask(submittedTask)
        startPollingSubmittedTask(submittedTask)
        return submittedTask
    }

    func updateTaskCompletionSummary(taskId: String, summary: String?) {
        guard let index = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        tasks[index] = tasks[index].withCompletionSummary(summary)
    }

    func handleStreamedTaskUpdate(_ task: Task) {
        upsertTask(task)
    }

    func resetRegistration() {
        keychain.delete(forKey: "device_id")
        keychain.delete(forKey: "api_key")
        deviceId = nil
        apiKey = nil
        registrationError = nil
        heartbeatService.stop()
    }

    private func startPollingSubmittedTask(_ task: Task) {
        let taskId = task.taskId
        taskPollingTasks[taskId]?.cancel()

        if task.isTerminal {
            notifyTaskArrived()
            return
        }

        taskPollingTasks[taskId] = _Concurrency.Task { [weak self] in
            await self?.pollSubmittedTaskUntilTerminal(taskId: taskId)
        }
    }

    private func pollSubmittedTaskUntilTerminal(taskId: String) async {
        defer { taskPollingTasks[taskId] = nil }

        while !_Concurrency.Task.isCancelled {
            do {
                try await _Concurrency.Task.sleep(for: .seconds(3))
                let updatedTask = try await client.getTask(taskId: taskId)
                upsertTask(updatedTask)

                if updatedTask.isTerminal {
                    notifyTaskArrived()
                    return
                }
            } catch is CancellationError {
                return
            } catch {
                listError = error.localizedDescription
            }
        }
    }

    private func upsertTask(_ task: Task) {
        let previousState = tasks.first(where: { $0.taskId == task.taskId })?.currentState

        if let index = tasks.firstIndex(where: { $0.taskId == task.taskId }) {
            let existingSummary = tasks[index].completionSummary
            var mergedTask = task
            if mergedTask.outputSummary == nil {
                mergedTask.outputSummary = tasks[index].outputSummary
            }
            tasks[index] = mergedTask.completionSummary == nil
                ? mergedTask.withCompletionSummary(existingSummary)
                : mergedTask
        } else {
            tasks.insert(task, at: 0)
        }

        if previousState != "completed", task.currentState == "completed" {
            notifyTaskCompletedIfNeeded(task)
        }
    }

    private func notifyTaskArrived() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func notifyTaskCompletedIfNeeded(_ task: Task) {
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState != .active else { return }
        #endif

        let summary = task.outputSummary ?? task.completionSummary ?? task.intentSummary
        NotificationService.shared.scheduleTaskCompletedNotification(
            taskTitle: task.taskTitle,
            summary: summary,
            taskId: task.taskId
        )
    }
}
