import Foundation

struct AppConfig {
    static let userDefaultsKey = "control_plane_url"
    static let onboardingCompleteKey = "onboarding_complete"
    static let defaultBaseURLString = "http://localhost:3000"

    var baseURL: URL

    /// Reads UserDefaults (settable from the Settings screen),
    /// then falls back to CONTROL_PLANE_BASE_URL from Info.plist (set via Xcode build settings),
    /// then falls back to the compile-time default below.
    ///
    /// To change the default without rebuilding: open the app's Settings screen
    /// and enter your Mac's local IP, e.g. http://192.168.1.x:3000
    static var current: AppConfig {
        AppConfig(
            baseURL: URL(
                string: UserDefaults.standard.string(forKey: userDefaultsKey)
                    ?? Bundle.main.object(forInfoDictionaryKey: "CONTROL_PLANE_BASE_URL") as? String
                    ?? defaultBaseURLString
            )!
        )
    }
}
