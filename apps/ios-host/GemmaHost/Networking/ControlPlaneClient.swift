import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct HeartbeatRequest: Codable {
    let deviceId: String
    let isOnline: Bool
    let networkType: String
    let activeRunCount: Int
    let supportedTools: [String]
    let supportedCapabilities: [String]

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case isOnline = "is_online"
        case networkType = "network_type"
        case activeRunCount = "active_run_count"
        case supportedTools = "supported_tools"
        case supportedCapabilities = "supported_capabilities"
    }
}

struct TaskActionPayload: Codable {
    let reason: String
}

struct CancelTaskRequest: Codable {
    let schemaVersion = "1.0.0"
    let eventType = "task.cancelled"
    let taskId: String
    let source = "mobile"
    let emittedAt: String
    let payload = TaskActionPayload(reason: "user_cancelled")

    init(taskId: String) {
        self.taskId = taskId
        self.emittedAt = ISO8601DateFormatter().string(from: Date())
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventType = "event_type"
        case taskId = "task_id"
        case source
        case emittedAt = "emitted_at"
        case payload
    }
}

struct RetryTaskRequest: Codable {
    let schemaVersion = "1.0.0"
    let eventType = "task.retry_requested"
    let taskId: String
    let source = "mobile"
    let emittedAt: String
    let payload = TaskActionPayload(reason: "user_retry")

    init(taskId: String) {
        self.taskId = taskId
        self.emittedAt = ISO8601DateFormatter().string(from: Date())
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventType = "event_type"
        case taskId = "task_id"
        case source
        case emittedAt = "emitted_at"
        case payload
    }
}


final class ControlPlaneClient {
    static let deviceAuthFailedNotification = Notification.Name("DeviceAuthFailed")

    private let baseURLProvider: () -> URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var apiKeyProvider: () -> String?
    private var deviceIdProvider: () -> String?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = { nil },
        deviceIdProvider: @escaping () -> String? = { nil }
    ) {
        self.baseURLProvider = { baseURL }
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.deviceIdProvider = deviceIdProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    convenience init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = { nil },
        deviceIdProvider: @escaping () -> String? = { nil }
    ) {
        self.init(
            baseURLProvider: { AppConfig.current.baseURL },
            session: session,
            apiKeyProvider: apiKeyProvider,
            deviceIdProvider: deviceIdProvider
        )
    }

    private init(
        baseURLProvider: @escaping () -> URL,
        session: URLSession,
        apiKeyProvider: @escaping () -> String?,
        deviceIdProvider: @escaping () -> String?
    ) {
        self.baseURLProvider = baseURLProvider
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.deviceIdProvider = deviceIdProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func updateApiKeyProvider(_ provider: @escaping () -> String?) {
        apiKeyProvider = provider
    }

    func updateDeviceIdProvider(_ provider: @escaping () -> String?) {
        deviceIdProvider = provider
    }

    func registerDevice(permissionScope: String = "private_lan") async throws -> DeviceRegistrationResponse {
        // UIDevice.current is @MainActor in Swift 6 — capture it on the main actor first.
        #if canImport(UIKit)
        let name = await MainActor.run {
            UIDevice.current.name.isEmpty ? "iOS Host" : UIDevice.current.name
        }
        #else
        let name = Host.current().localizedName ?? "iOS Host"
        #endif
        let request = DeviceRegistrationRequest(
            deviceName: name,
            runtimeType: "mobile",
            permissionScope: permissionScope
        )
        return try await send("v1/devices", method: "POST", body: request)
    }

    func verifyDevice(deviceId: String) async -> Bool {
        do {
            let _: Device = try await send("v1/devices/\(deviceId)")
            return true
        } catch {
            return false
        }
    }

    func postHeartbeat(_ heartbeat: HeartbeatRequest) async throws {
        try await sendNoContent("v1/heartbeat", method: "POST", body: heartbeat)
    }

    func submitTask(_ draft: TaskDraft) async throws -> Task {
        try await send("v1/tasks", method: "POST", body: draft)
    }

    func listTasks(limit: Int = 50, before: String? = nil) async throws -> TasksResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: before))
        }
        return try await send("v1/tasks", queryItems: query)
    }

    func getTask(taskId: String) async throws -> Task {
        try await send("v1/tasks/\(taskId)")
    }

    func getEvents(taskId: String, limit: Int = 50, before: String? = nil) async throws -> EventsResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let before {
            query.append(URLQueryItem(name: "before", value: before))
        }
        return try await send("v1/tasks/\(taskId)/events", queryItems: query)
    }

    func fetchEvents(taskId: String, limit: Int) async throws -> [TaskEvent] {
        let query = [URLQueryItem(name: "limit", value: String(limit))]
        let response: TaskEventsResponse = try await send("v1/tasks/\(taskId)/events", queryItems: query)
        return response.events
    }

    func cancelTask(taskId: String) async throws {
        let body = CancelTaskRequest(taskId: taskId)
        try await sendNoContent("v1/tasks/\(taskId)/events", method: "POST", body: body)
    }

    func retryTask(taskId: String) async throws {
        let body = RetryTaskRequest(taskId: taskId)
        try await sendNoContent("v1/tasks/\(taskId)/events", method: "POST", body: body)
    }

    /// 通过 SSE 实时流式接收任务状态更新。
    /// 每次服务端推送状态变化时 yield 一个 Task。
    /// 任务达到 terminal 状态或连接断开时 stream 结束。
    func streamTaskUpdates(taskId: String) -> AsyncThrowingStream<Task, Error> {
        AsyncThrowingStream { continuation in
            let taskHandle = _Concurrency.Task {
                do {
                    guard var components = URLComponents(
                        url: baseURLProvider().appendingPathComponent("v1/tasks/\(taskId)/stream"),
                        resolvingAgainstBaseURL: false
                    ) else {
                        continuation.finish(throwing: ControlPlaneError.invalidURL)
                        return
                    }
                    components.queryItems = nil
                    guard let url = components.url else {
                        continuation.finish(throwing: ControlPlaneError.invalidURL)
                        return
                    }
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let apiKey = apiKeyProvider(), !apiKey.isEmpty {
                        request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.timeoutInterval = 300
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode) else {
                        if let httpResponse = response as? HTTPURLResponse {
                            notifyDeviceAuthFailedIfNeeded(statusCode: httpResponse.statusCode)
                        }
                        continuation.finish(throwing: ControlPlaneError.invalidResponse)
                        return
                    }
                    var buffer = ""
                    for try await byte in bytes {
                        guard let char = String(bytes: [byte], encoding: .utf8) else { continue }
                        buffer += char
                        while let range = buffer.range(of: "\n\n") {
                            let message = String(buffer[buffer.startIndex..<range.lowerBound])
                            buffer = String(buffer[range.upperBound...])
                            for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
                                let lineStr = String(line)
                                guard lineStr.hasPrefix("data: ") else { continue }
                                let jsonStr = String(lineStr.dropFirst(6))
                                guard let data = jsonStr.data(using: .utf8),
                                      let task = try? decoder.decode(Task.self, from: data) else {
                                    continue
                                }
                                continuation.yield(task)
                                if task.isTerminal {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                taskHandle.cancel()
            }
        }
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request: URLRequest = try makeRequest(path, method: method, queryItems: queryItems)
        return try await decode(request)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(path, method: method)
        request.httpBody = try encoder.encode(body)
        return try await decode(request)
    }

    private func sendNoContent<Body: Encodable>(
        _ path: String,
        method: String,
        body: Body
    ) async throws {
        var request = try makeRequest(path, method: method)
        request.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ControlPlaneError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            notifyDeviceAuthFailedIfNeeded(statusCode: httpResponse.statusCode)
            throw ControlPlaneError.httpStatus(httpResponse.statusCode, nil)
        }
    }

    private func makeRequest(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURLProvider().appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw ControlPlaneError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ControlPlaneError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKeyProvider(), !apiKey.isEmpty {
            request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decode<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ControlPlaneError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            notifyDeviceAuthFailedIfNeeded(statusCode: httpResponse.statusCode)
            throw ControlPlaneError.httpStatus(httpResponse.statusCode, message)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func notifyDeviceAuthFailedIfNeeded(statusCode: Int) {
        if statusCode == 401, deviceIdProvider() != nil {
            NotificationCenter.default.post(name: Self.deviceAuthFailedNotification, object: nil)
        }
    }
}

enum ControlPlaneError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The control plane URL is invalid."
        case .invalidResponse:
            return "The control plane returned an invalid response."
        case .httpStatus(let status, let message):
            return "Control plane request failed with HTTP \(status): \(message ?? "no response body")."
        }
    }
}
