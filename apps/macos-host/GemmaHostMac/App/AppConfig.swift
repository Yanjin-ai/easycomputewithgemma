import Foundation

struct AppConfig {
    var baseURL: URL

    static let current = AppConfig(
        baseURL: URL(
            string: Bundle.main.infoDictionary?["CONTROL_PLANE_BASE_URL"] as? String
                ?? "http://localhost:3000"
        )!
    )
}
