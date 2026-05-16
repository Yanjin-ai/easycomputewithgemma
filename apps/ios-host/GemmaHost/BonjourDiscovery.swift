import Combine
import Foundation
import SwiftUI

@MainActor
final class BonjourDiscovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var isSearching = false

    struct DiscoveredHost: Identifiable, Equatable {
        let id: String
        let name: String
        var baseURL: URL?
        var isResolving: Bool
    }

    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    private var searchTask: _Concurrency.Task<Void, Never>?

    func startSearch() {
        stopSearch()
        discoveredHosts = []
        isSearching = true

        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: "_gemma4all._tcp.", inDomain: "local.")

        searchTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.isSearching else {
                return
            }

            self.stopSearch()
        }
    }

    func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        browser?.stop()
        browser = nil
        isSearching = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let serviceID = service.name
        guard !discoveredHosts.contains(where: { $0.id == serviceID }) else {
            return
        }

        discoveredHosts.append(
            DiscoveredHost(
                id: serviceID,
                name: displayName(for: service.name),
                baseURL: nil,
                isResolving: true
            )
        )

        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        discoveredHosts.removeAll { $0.id == service.name }
        resolvingServices.removeAll { $0.name == service.name }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        isSearching = false
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer {
            resolvingServices.removeAll { $0 === sender }
        }

        guard let ipv4Address = sender.addresses?.compactMap(ipv4Address(from:)).first,
              let url = URL(string: "http://\(ipv4Address):\(sender.port)") else {
            markResolutionFailed(for: sender)
            return
        }

        updateHost(sender.name) { host in
            host.baseURL = url
            host.isResolving = false
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolvingServices.removeAll { $0 === sender }
        markResolutionFailed(for: sender)
    }

    private func markResolutionFailed(for service: NetService) {
        updateHost(service.name) { host in
            host.isResolving = false
        }
    }

    private func updateHost(_ id: String, update: (inout DiscoveredHost) -> Void) {
        guard let index = discoveredHosts.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&discoveredHosts[index])
    }

    private func displayName(for serviceName: String) -> String {
        serviceName.replacingOccurrences(of: "-", with: " ")
    }

    private func ipv4Address(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer -> String? in
            guard let sockaddrPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  sockaddrPointer.pointee.sa_family == sa_family_t(AF_INET) else {
                return nil
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddrPointer,
                socklen_t(sockaddrPointer.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                return nil
            }

            let address = String(cString: host)
            guard !address.hasPrefix("169.254."), address != "127.0.0.1" else {
                return nil
            }

            return address
        }
    }
}

struct BonjourDiscoverySection: View {
    @ObservedObject var discovery: BonjourDiscovery

    let scanButtonTitle: String
    let selectedURLString: String
    let onSelect: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Auto-discover Mac")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if discovery.isSearching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Scanning...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(scanButtonTitle) {
                        discovery.startSearch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !discovery.discoveredHosts.isEmpty {
                ForEach(discovery.discoveredHosts) { host in
                    Button {
                        if let url = host.baseURL {
                            onSelect(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "desktopcomputer")

                            VStack(alignment: .leading) {
                                Text(host.name)
                                    .font(.subheadline)

                                if let url = host.baseURL {
                                    Text(url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if host.isResolving {
                                    Text("Resolving...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if let url = host.baseURL,
                               selectedURLString == url.absoluteString {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(host.baseURL == nil)
                }
            } else if !discovery.isSearching {
                Text("No Gemma4all Macs found on this network. 确认 Mac 上的 Gemma4all 菜单栏 App 正在运行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
