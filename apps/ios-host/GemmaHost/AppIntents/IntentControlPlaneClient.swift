import Foundation

final class IntentControlPlaneClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let apiKeyProvider: () -> String?

    init(
        baseURL: URL = IntentControlPlaneClient.resolveBaseURL(),
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = { KeychainHelper.shared.string(forKey: "api_key") }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.apiKeyProvider = apiKeyProvider
    }

    func submitTask(text: String) async throws -> Task {
        let draft = TaskDraft(
            intent: text,
            goal: ["description": .string(text)],
            requiredTools: [],
            requiredCapabilities: ["cpu_inference"],
            complexityHint: "light",
            permissionLevel: "private_lan",
            rawInput: text,
            intentSummary: text,
            taskTitle: String(text.prefix(60))
        )
        return try await send("v1/tasks", method: "POST", body: draft)
    }

    func getTask(taskId: String) async throws -> Task {
        try await send("v1/tasks/\(taskId)")
    }

    private static func resolveBaseURL() -> URL {
        let appGroupDefaults = UserDefaults(suiteName: "group.com.gemma4all.host")
        let urlString = appGroupDefaults?.string(forKey: AppConfig.userDefaultsKey)
            ?? UserDefaults.standard.string(forKey: AppConfig.userDefaultsKey)
            ?? Bundle.main.object(forInfoDictionaryKey: "CONTROL_PLANE_BASE_URL") as? String
            ?? AppConfig.defaultBaseURLString

        return URL(string: urlString) ?? URL(string: AppConfig.defaultBaseURLString)!
    }

    private func send<Response: Decodable>(
        _ path: String,
        method: String = "GET"
    ) async throws -> Response {
        let request = try makeRequest(path, method: method)
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

    private func makeRequest(_ path: String, method: String) throws -> URLRequest {
        guard let url = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )?.url else {
            throw IntentControlPlaneError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKeyProvider(), !apiKey.isEmpty {
            request.setValue("ApiKey \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decode<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw IntentControlPlaneError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                throw IntentControlPlaneError.httpStatus(httpResponse.statusCode, message)
            }
            return try decoder.decode(Response.self, from: data)
        } catch let error as URLError where [
            .cannotConnectToHost,
            .cannotFindHost,
            .networkConnectionLost,
            .notConnectedToInternet,
            .timedOut
        ].contains(error.code) {
            throw IntentControlPlaneError.notReachable
        }
    }
}

enum IntentControlPlaneError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String?)
    case notReachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Control plane URL is invalid."
        case .invalidResponse:
            return "Gemma4all returned an invalid response."
        case .httpStatus(let code, let message):
            return message ?? "Gemma4all request failed with HTTP \(code)."
        case .notReachable:
            return "Cannot reach your Mac."
        }
    }
}
