import Foundation
import SwiftUI

@MainActor
final class ServiceManager: ObservableObject {
    @Published private(set) var controlPlaneState: ServiceState = .unknown {
        didSet {
            updateBonjourAdvertising(from: oldValue, to: controlPlaneState)
        }
    }
    @Published private(set) var desktopRuntimeState: ServiceState = .unknown

    enum ServiceState {
        case unknown
        case starting
        case running
        case stopped
        case failed(String)

        var displayText: String {
            switch self {
            case .unknown:
                return "Unknown"
            case .starting:
                return "Starting..."
            case .running:
                return "Running"
            case .stopped:
                return "Stopped"
            case .failed(let message):
                return "Error: \(message)"
            }
        }

        var color: Color {
            switch self {
            case .running:
                return .green
            case .starting:
                return .orange
            case .stopped, .failed:
                return .red
            case .unknown:
                return .gray
            }
        }

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }
    }

    private let healthURL = URL(string: "http://localhost:3000/health")!
    private let launchdLabel = "com.gemma4all.runtime"
    private let bonjourRegistrar: BonjourRegistrar
    private var healthTask: Task<Void, Never>?
    private var spawnedProcess: Process?
    private var usesLaunchd = false

    init(bonjourRegistrar: BonjourRegistrar) {
        self.bonjourRegistrar = bonjourRegistrar
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkStatus()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    deinit {
        healthTask?.cancel()
    }

    private func updateBonjourAdvertising(from oldState: ServiceState, to newState: ServiceState) {
        if newState.isRunning, !oldState.isRunning {
            bonjourRegistrar.startAdvertising()
            return
        }

        switch newState {
        case .stopped, .failed:
            bonjourRegistrar.stopAdvertising()
        case .unknown, .starting, .running:
            break
        }
    }

    func checkStatus() async {
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode) {
                controlPlaneState = .running
                desktopRuntimeState = .running
            } else {
                controlPlaneState = .stopped
                desktopRuntimeState = .stopped
            }
        } catch {
            controlPlaneState = .stopped
            desktopRuntimeState = .stopped
        }
    }

    func startServices() async {
        controlPlaneState = .starting
        desktopRuntimeState = .starting

        if await isLaunchdInstalled() {
            usesLaunchd = true
            let result = await runLaunchctl(arguments: ["start", launchdLabel])
            if result.exitCode != 0 {
                let message = result.output.isEmpty ? "launchctl start failed" : result.output
                controlPlaneState = .failed(message)
                desktopRuntimeState = .failed(message)
            }
            return
        }

        usesLaunchd = false
        if let scriptURL = findStartAllScript() {
            startFromScript(scriptURL)
            return
        }

        guard let binaryURL = findBundledControlPlaneBinary() else {
            let message = "Run: bash scripts/install_autostart.sh first, or bundle gemma4all-cp-macos"
            controlPlaneState = .failed(message)
            desktopRuntimeState = .failed(message)
            return
        }

        startFromBinary(binaryURL)
    }

    private func startFromScript(_ scriptURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        do {
            try process.run()
            spawnedProcess = process
        } catch {
            let message = error.localizedDescription
            controlPlaneState = .failed(message)
            desktopRuntimeState = .failed(message)
        }
    }

    private func startFromBinary(_ binaryURL: URL) {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let dbDirectoryURL = homeURL.appendingPathComponent(".gemma4all")

        try? FileManager.default.createDirectory(
            at: dbDirectoryURL,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = []
        process.environment = [
            "PORT": "3000",
            "DB_PATH": dbDirectoryURL.appendingPathComponent("control-plane.sqlite").path,
            "HOME": homeURL.path
        ]

        do {
            try process.run()
            spawnedProcess = process
        } catch {
            let message = error.localizedDescription
            controlPlaneState = .failed(message)
            desktopRuntimeState = .failed(message)
        }
    }

    func stopServices() async {
        if usesLaunchd {
            _ = await runLaunchctl(arguments: ["stop", launchdLabel])
        } else {
            spawnedProcess?.terminate()
            spawnedProcess = nil
        }

        controlPlaneState = .stopped
        desktopRuntimeState = .stopped
    }

    private func isLaunchdInstalled() async -> Bool {
        let result = await runLaunchctl(arguments: ["list", launchdLabel])
        return result.exitCode == 0
    }

    private func runLaunchctl(arguments: [String]) async -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: (process.terminationStatus, output))
            }

            Task {
                do {
                    try await MainActor.run {
                        try process.run()
                    }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(returning: (1, error.localizedDescription))
                }
            }
        }
    }

    private func findStartAllScript() -> URL? {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            homeURL.appendingPathComponent("Applications/Gemma4all/scripts/start_all.sh"),
            homeURL.appendingPathComponent(".gemma4all/scripts/start_all.sh")
        ] + userDefaultsScriptCandidates(named: "start_all.sh")

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) || FileManager.default.fileExists(atPath: $0.path) }
    }

    private func findBundledControlPlaneBinary() -> URL? {
        let binaryName = "gemma4all-cp-macos"
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(binaryName))
        }

        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("../Resources/\(binaryName)")
                    .standardizedFileURL
            )
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) || FileManager.default.fileExists(atPath: $0.path) }
    }

    private func userDefaultsScriptCandidates(named scriptName: String) -> [URL] {
        guard let repoPath = UserDefaults.standard.string(forKey: "repo_path"),
              !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return [
            URL(fileURLWithPath: repoPath)
                .appendingPathComponent("scripts")
                .appendingPathComponent(scriptName)
        ]
    }
}
