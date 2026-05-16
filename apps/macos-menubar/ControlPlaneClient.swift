import Foundation

final class ControlPlaneClient {
    static let fallbackBaseURL = URL(string: "http://localhost:3000")!

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var apiKeyProvider: () -> String?

    init(
        baseURL: URL = ControlPlaneClient.baseURLFromDefaults(),
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = { nil }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func updateApiKeyProvider(_ provider: @escaping () -> String?) {
        apiKeyProvider = provider
    }

    func registerDevice() async throws -> DeviceRegistrationResponse {
        let request = DeviceRegistrationRequest(
            deviceName: Host.current().localizedName ?? "Mac Menu Bar",
            runtimeType: "mobile",
            permissionScope: "private_lan"
        )
        return try await send("v1/devices", method: "POST", body: request)
    }

    func submitTask(intent: String) async throws {
        let request = TaskSubmissionRequest(
            schemaVersion: "1.0.0",
            intent: intent,
            goal: TaskGoal(description: intent),
            requiredTools: [],
            requiredCapabilities: [],
            complexityHint: "light",
            permissionLevel: "private_lan",
            rawInput: intent
        )
        try await sendNoResponse("v1/tasks", method: "POST", body: request)
    }

    func listTasks(limit: Int = 10) async throws -> [GemmaTask] {
        let response: TaskListResponse = try await send(
            "v1/tasks",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.tasks
    }

    func getTask(taskId: String) async throws -> GemmaTask {
        try await send("v1/tasks/\(taskId)")
    }

    func fetchEvents(taskId: String, limit: Int) async throws -> [TaskEvent] {
        let response: TaskEventsResponse = try await send(
            "v1/tasks/\(taskId)/events",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return response.events
    }

    func streamTaskUpdates(taskId: String) -> AsyncThrowingStream<GemmaTask, Error> {
        AsyncThrowingStream { continuation in
            let taskHandle = _Concurrency.Task {
                do {
                    let url = baseURL.appendingPathComponent("v1/tasks/\(taskId)/stream")
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
                        continuation.finish(throwing: ControlPlaneError.invalidResponse)
                        return
                    }

                    var buffer = ""
                    for try await byte in bytes {
                        guard let char = String(bytes: [byte], encoding: .utf8) else {
                            continue
                        }
                        buffer += char
                        while let range = buffer.range(of: "\n\n") {
                            let message = String(buffer[buffer.startIndex..<range.lowerBound])
                            buffer = String(buffer[range.upperBound...])
                            for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
                                let lineString = String(line)
                                guard lineString.hasPrefix("data: ") else {
                                    continue
                                }
                                let jsonString = String(lineString.dropFirst(6))
                                guard let data = jsonString.data(using: .utf8),
                                      let task = try? decoder.decode(GemmaTask.self, from: data) else {
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

    private static func baseURLFromDefaults() -> URL {
        guard let value = UserDefaults.standard.string(forKey: "control_plane_url")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let url = URL(string: value) else {
            return fallbackBaseURL
        }
        return url
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(path, method: method, queryItems: queryItems)
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

    private func sendNoResponse<Body: Encodable>(
        _ path: String,
        method: String,
        body: Body
    ) async throws {
        var request = try makeRequest(path, method: method)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ControlPlaneError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ControlPlaneError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
    }

    private func makeRequest(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
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
            throw ControlPlaneError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }
        return try decoder.decode(Response.self, from: data)
    }
}

enum ControlPlaneError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Control plane URL is invalid."
        case .invalidResponse:
            return "Control plane returned an invalid response."
        case .httpStatus(let status, let body):
            return "Control plane request failed with HTTP \(status): \(body ?? "no response body")."
        }
    }
}
