import SwiftUI

struct PermissionPicker: View {
    @Binding var permissionLevel: String

    private let levels = ["local_only", "private_lan", "cloud_ok"]

    var body: some View {
        Picker("permission_level", selection: $permissionLevel) {
            ForEach(levels, id: \.self) { level in
                Text(level).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
}
