import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    let onComplete: () -> Void

    @State private var page = 0
    @State private var baseURLString: String
    @State private var validationError: String?
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var isTestingConnection = false

    private let runtimeCommand = "bash scripts/start_all.sh"

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _baseURLString = State(
            initialValue: UserDefaults.standard.string(forKey: AppConfig.userDefaultsKey)
                ?? AppConfig.defaultBaseURLString
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                introPage
                    .tag(0)

                setupPage
                    .tag(1)

                connectionPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }

    private var introPage: some View {
        OnboardingPage(
            systemImage: "lock.shield.fill",
            symbolColor: .blue,
            title: "Your AI, Your Rules",
            bodyText: "GemmaHost runs Gemma 4 on your own Mac. Your tasks never leave your home network — no cloud, no subscriptions, no data collection."
        )
    }

    private var setupPage: some View {
        VStack(spacing: 28) {
            OnboardingPageHeader(
                systemImage: "desktopcomputer",
                symbolColor: .blue,
                title: "Mac Does the Thinking"
            )

            VStack(alignment: .leading, spacing: 16) {
                Text("Run the Gemma desktop runtime on your Mac:")

                HStack(spacing: 12) {
                    Text(runtimeCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        copyRuntimeCommand()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy command")
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                Text("Same WiFi: use Mac's LAN IP. Anywhere: install Tailscale on both devices and use Tailscale IP.")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionPage: some View {
        VStack(spacing: 28) {
            OnboardingPageHeader(
                systemImage: "wifi",
                symbolColor: .green,
                title: "Connect to Your Mac"
            )

            VStack(alignment: .leading, spacing: 16) {
                Text("Enter your Mac's local IP address.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "e.g. http://100.x.x.x:3000 (Tailscale) or http://192.168.x.x:3000 (LAN)",
                        text: $baseURLString
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .onChange(of: baseURLString) {
                            validationError = nil
                            connectionStatus = .idle
                        }

                    if let validationError {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Button {
                    _Concurrency.Task {
                        await testConnection()
                    }
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                        } else {
                            Image(systemName: "network")
                        }

                        Text("Test Connection")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTestingConnection)

                statusView
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var statusView: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .failed(let message):
            Label("Not reachable", systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack {
            if page > 0 {
                Button("Back") {
                    withAnimation {
                        page -= 1
                    }
                }
            }

            Spacer()

            if page < 2 {
                Button("Next") {
                    withAnimation {
                        page += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    UserDefaults.standard.set(baseURLString.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppConfig.userDefaultsKey)
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectionStatus != .connected)
            }
        }
    }

    private func testConnection() async {
        guard let url = validateBaseURL() else {
            return
        }

        isTestingConnection = true
        connectionStatus = .idle
        defer { isTestingConnection = false }

        do {
            let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: AppConfig.userDefaultsKey)
            await model.bootstrap()

            let client = ControlPlaneClient(baseURL: url, apiKeyProvider: { model.apiKey })
            _ = try await client.listTasks(limit: 1)
            connectionStatus = .connected
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
    }

    private func validateBaseURL() -> URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            validationError = "URL must start with http:// or https://."
            connectionStatus = .idle
            return nil
        }

        guard let url = URL(string: trimmed), url.host != nil else {
            validationError = "Enter a valid control plane URL."
            connectionStatus = .idle
            return nil
        }

        validationError = nil
        return url
    }

    private func copyRuntimeCommand() {
        #if canImport(UIKit)
        UIPasteboard.general.string = runtimeCommand
        #endif
    }
}

private struct OnboardingPage: View {
    let systemImage: String
    let symbolColor: Color
    let title: String
    let bodyText: String

    var body: some View {
        VStack(spacing: 28) {
            OnboardingPageHeader(
                systemImage: systemImage,
                symbolColor: symbolColor,
                title: title
            )

            Text(bodyText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingPageHeader: View {
    let systemImage: String
    let symbolColor: Color
    let title: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
        }
    }
}

private enum ConnectionStatus: Equatable {
    case idle
    case connected
    case failed(String)
}
