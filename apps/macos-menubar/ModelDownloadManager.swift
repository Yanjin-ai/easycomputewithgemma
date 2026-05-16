import Foundation

@MainActor
final class ModelDownloadManager: ObservableObject {
    @Published private(set) var state: ModelState = .checking

    enum ModelState {
        case checking
        case notFound
        case downloading(progress: Double, bytesReceived: Int64, totalBytes: Int64)
        case ready(path: String)
        case failed(String)
    }

    private let e2bModelName = "gemma-4-E2B-it.litertlm"
    private let e4bModelName = "gemma-4-E4B-it.litertlm"
    private var downloadProcess: Process?

    func checkModel() {
        let modelsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("models")
        let candidates = [
            modelsURL.appendingPathComponent(e2bModelName),
            modelsURL.appendingPathComponent(e4bModelName)
        ]

        if let modelURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            state = .ready(path: modelURL.path)
        } else {
            state = .notFound
        }
    }

    func downloadModel(variant: String) {
        Task {
            await startDownload(variant: variant)
        }
    }

    private func startDownload(variant: String) async {
        guard downloadProcess == nil else {
            return
        }

        guard let scriptURL = findCheckModelsScript() else {
            state = .failed("Script not found at scripts/check_models.sh")
            return
        }

        state = .downloading(progress: 0, bytesReceived: 0, totalBytes: 0)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = variant.lowercased() == "e4b" ? [scriptURL.path, "--e4b"] : [scriptURL.path]
        process.currentDirectoryURL = scriptURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else {
                return
            }

            Task { @MainActor in
                self?.updateProgress(from: output)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.downloadProcess = nil
                if process.terminationStatus == 0 {
                    self?.checkModel()
                } else {
                    self?.state = .failed("Model download failed")
                }
            }
        }

        do {
            downloadProcess = process
            try await MainActor.run {
                try process.run()
            }
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            downloadProcess = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func updateProgress(from output: String) {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)%"#) else {
            return
        }

        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.matches(in: output, range: range).last,
              let percentRange = Range(match.range(at: 1), in: output),
              let percent = Double(output[percentRange]) else {
            return
        }

        let progress = min(max(percent / 100, 0), 1)
        state = .downloading(progress: progress, bytesReceived: 0, totalBytes: 0)
    }

    private func findCheckModelsScript() -> URL? {
        let candidates = userDefaultsScriptCandidates(named: "check_models.sh") + currentDirectoryScriptCandidates(named: "check_models.sh")
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

    private func currentDirectoryScriptCandidates(named scriptName: String) -> [URL] {
        [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts")
                .appendingPathComponent(scriptName)
        ]
    }
}
