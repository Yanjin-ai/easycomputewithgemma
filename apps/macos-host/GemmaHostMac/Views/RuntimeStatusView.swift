import SwiftUI

struct RuntimeStatusView: View {
    @EnvironmentObject private var model: MacAppModel

    private var isRegistered: Bool {
        model.deviceId?.isEmpty == false
    }

    private var shortDeviceId: String {
        guard let deviceId = model.deviceId, !deviceId.isEmpty else {
            return "unregistered"
        }
        return String(deviceId.suffix(8))
    }

    private var activeTaskCount: Int {
        model.tasks.filter { $0.currentState == "running" }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRegistered ? Color.green : Color.red)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text("Desktop runtime")
                    .font(.subheadline.weight(.medium))
                Text("\(shortDeviceId) - \(activeTaskCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
