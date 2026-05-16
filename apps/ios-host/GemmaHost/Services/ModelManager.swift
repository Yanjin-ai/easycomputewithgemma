import Foundation

@MainActor
final class ModelManager: ObservableObject {
    enum State {
        case notDownloaded
        case downloading(Double)
        case ready(URL)
        case failed(String)
    }

    @Published var state: State = .notDownloaded

    static let modelFileName = "gemma3-1b-it.task"
    // Kaggle direct download URL for gemma3-1b-it-cpu-int4 .task file.
    // Set MODEL_DOWNLOAD_URL in Info.plist so the URL can be updated without code changes.

    var modelURL: URL? {
        guard case .ready(let url) = state else { return nil }
        return url
    }

    var isOnDeviceInferenceAvailable: Bool {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "MODEL_DOWNLOAD_URL") as? String else {
            return false
        }

        return !url.isEmpty
    }

    func bootstrap() async {
        let dest = localModelURL()
        if FileManager.default.fileExists(atPath: dest.path) {
            state = .ready(dest)
            return
        }

        await download()
    }

    private func localModelURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.modelFileName)
    }

    func download() async {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "MODEL_DOWNLOAD_URL") as? String,
              let url = URL(string: urlString) else {
            state = .failed("MODEL_DOWNLOAD_URL not set in Info.plist")
            return
        }

        state = .downloading(0)

        do {
            let dest = localModelURL()
            let tempURL = dest.appendingPathExtension("download")

            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }

            try await Self.downloadFile(from: url, to: tempURL) { [weak self] progress in
                await MainActor.run {
                    self?.state = .downloading(progress)
                }
            }

            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }

            try FileManager.default.moveItem(at: tempURL, to: dest)
            state = .ready(dest)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func downloadFile(
        from url: URL,
        to destination: URL,
        progressHandler: @escaping (Double) async -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let expectedSize = response.expectedContentLength.nonNegative
        FileManager.default.createFile(atPath: destination.path, contents: nil)

        let fileHandle = try FileHandle(forWritingTo: destination)
        defer {
            try? fileHandle.close()
        }

        var receivedBytes: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64 * 1024)

        for try await byte in bytes {
            buffer.append(byte)

            if buffer.count >= 64 * 1024 {
                try fileHandle.write(contentsOf: Data(buffer))
                receivedBytes += Int64(buffer.count)
                await reportProgress(receivedBytes: receivedBytes, expectedSize: expectedSize, progressHandler: progressHandler)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: Data(buffer))
            receivedBytes += Int64(buffer.count)
        }

        await reportProgress(receivedBytes: receivedBytes, expectedSize: expectedSize, progressHandler: progressHandler)
    }

    nonisolated private static func reportProgress(
        receivedBytes: Int64,
        expectedSize: Int64?,
        progressHandler: @escaping (Double) async -> Void
    ) async {
        guard let expectedSize, expectedSize > 0 else {
            await progressHandler(0)
            return
        }

        await progressHandler(min(Double(receivedBytes) / Double(expectedSize), 1))
    }
}

private extension Int64 {
    var nonNegative: Int64? {
        self >= 0 ? self : nil
    }
}
