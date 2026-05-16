import Foundation
import Network

@MainActor
final class BonjourRegistrar {
    private var listener: NWListener?
    private var isRegistered = false

    func startAdvertising(port: UInt16 = 3000) {
        guard !isRegistered else {
            return
        }

        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            return
        }

        do {
            let parameters = NWParameters.tcp
            let listener = try NWListener(using: parameters, on: endpointPort)
            let hostName = Host.current().localizedName?
                .replacingOccurrences(of: ".local", with: "")
                ?? ProcessInfo.processInfo.hostName
                    .replacingOccurrences(of: ".local", with: "")

            listener.service = NWListener.Service(
                name: hostName,
                type: "_gemma4all._tcp",
                txtRecord: NWTXTRecord([
                    "version": "1.0",
                    "platform": "macos"
                ])
            )
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .failed = state else {
                    return
                }

                Task { @MainActor in
                    self?.stopAdvertising()
                }
            }

            self.listener = listener
            isRegistered = true
            listener.start(queue: .main)
        } catch {
            listener = nil
            isRegistered = false
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isRegistered = false
    }
}
