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


final class ControlPlaneClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var apiKeyProvider: () -> String?

    init(
        baseURL: URL = AppConfig.current.baseURL,
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

    func registerDevice(permissionScope: String = "private_lan") async throws -> DeviceRegistrationResponse {
        #if canImport(UIKit)
        let name = UIDevice.current.name.isEmpty ? "iOS Host" : UIDevice.current.name
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
            throw ControlPlaneError.httpStatus(httpResponse.statusCode, nil)
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
            let message = String(data: data, encoding: .utf8)
            throw ControlPlaneError.httpStatus(httpResponse.statusCode, message)
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
            return "The control plane URL is invalid."
        case .invalidResponse:
            return "The control plane returned an invalid response."
        case .httpStatus(let status, let message):
            return "Control plane request failed with HTTP \(status): \(message ?? "no response body")."
        }
    }
}
