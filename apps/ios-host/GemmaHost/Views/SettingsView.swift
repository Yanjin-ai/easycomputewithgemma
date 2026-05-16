import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    @State private var baseURLString: String
    @State private var validationError: String?
    @State private var connectionStatus: String?
    @State private var isTestingConnection = false
    @State private var resetStatus: String?
    @State private var isResettingRegistration = false
    @StateObject private var discovery = BonjourDiscovery()

    init() {
        _baseURLString = State(
            initialValue: UserDefaults.standard.string(forKey: AppConfig.userDefaultsKey)
                ?? AppConfig.defaultBaseURLString
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Control Plane") {
                    TextField(
                        "e.g. http://100.x.x.x:3000 (Tailscale) or http://192.168.x.x:3000 (LAN)",
                        text: $baseURLString
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                    Text("Same WiFi: use Mac's LAN IP. Anywhere: install Tailscale on both devices and use Tailscale IP.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    BonjourDiscoverySection(
                        discovery: discovery,
                        scanButtonTitle: "Rescan",
                        selectedURLString: baseURLString
                    ) { url in
                        baseURLString = url.absoluteString
                        save()
                    }

                    if let validationError {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if let connectionStatus {
                        Text(connectionStatus)
                            .font(.footnote)
                    }

                    HStack {
                        Button("Save") {
                            save()
                        }

                        Spacer()

                        Button {
                            _Concurrency.Task {
                                await testConnection()
                            }
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .disabled(isTestingConnection)
                    }
                }

                Section("Device") {
                    LabeledContent("device_id") {
                        Text(model.deviceId ?? "Not registered")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        _Concurrency.Task {
                            await resetAndRegisterDevice()
                        }
                    } label: {
                        if isResettingRegistration {
                            ProgressView()
                        } else {
                            Text("Reset Registration")
                        }
                    }
                    .disabled(isResettingRegistration)

                    if let resetStatus {
                        Text(resetStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Onboarding") {
                    Button("Reset Onboarding") {
                        UserDefaults.standard.set(false, forKey: AppConfig.onboardingCompleteKey)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        guard validateBaseURL() != nil else {
            return
        }

        UserDefaults.standard.set(baseURLString.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppConfig.userDefaultsKey)
        validationError = nil
        connectionStatus = "Saved"
    }

    private func testConnection() async {
        guard let url = validateBaseURL() else {
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let client = ControlPlaneClient(baseURL: url, apiKeyProvider: { model.apiKey })
            _ = try await client.listTasks(limit: 1)
            connectionStatus = "✅ Connected"
        } catch {
            connectionStatus = "❌ Failed: \(error.localizedDescription)"
        }
    }

    private func resetAndRegisterDevice() async {
        isResettingRegistration = true
        resetStatus = nil
        defer { isResettingRegistration = false }

        model.resetRegistration()
        await model.bootstrap()

        if let error = model.registrationError {
            resetStatus = "❌ Failed: \(error)"
        } else if model.deviceId != nil {
            resetStatus = "✅ Re-registered"
        } else {
            resetStatus = "❌ Failed to re-register"
        }
    }

    @discardableResult
    private func validateBaseURL() -> URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            validationError = "URL must start with http:// or https://."
            connectionStatus = nil
            return nil
        }

        guard let url = URL(string: trimmed), url.host != nil else {
            validationError = "Enter a valid control plane URL."
            connectionStatus = nil
            return nil
        }

        validationError = nil
        return url
    }
}
