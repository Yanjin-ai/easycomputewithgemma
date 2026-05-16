import Foundation

@MainActor
final class HeartbeatService {
    private let client: ControlPlaneClient
    private var timer: Timer?
    private var deviceId: String?

    init(client: ControlPlaneClient) {
        self.client = client
    }

    func start(deviceId: String) {
        stop()
        self.deviceId = deviceId
        sendHeartbeat()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                self?.sendHeartbeat()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sendHeartbeat() {
        guard let deviceId else { return }
        let heartbeat = HeartbeatRequest(
            deviceId: deviceId,
            isOnline: true,
            networkType: "wifi",
            activeRunCount: 0,
            supportedTools: [],
            supportedCapabilities: []
        )
        _Concurrency.Task {
            _ = try? await client.postHeartbeat(heartbeat)
        }
    }
}
