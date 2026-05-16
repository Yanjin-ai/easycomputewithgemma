import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: MacAppModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gemma Host")
                    .font(.headline)
                Spacer()
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            RuntimeStatusView()

            if let registrationError = model.registrationError {
                Text(registrationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            QuickInputView()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.tasks.prefix(10)) { task in
                        TaskRowView(task: task)
                    }

                    if model.tasks.isEmpty {
                        Text(model.isLoadingTasks ? "Loading tasks..." : "No tasks yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 18)
                    }
                }
            }
            .frame(maxHeight: 360)

            if let listError = model.listError {
                Text(listError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                TaskListWindow.open(model: model)
            } label: {
                Text("View All")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .top)
        .frame(maxHeight: 600, alignment: .top)
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
                .environmentObject(model)
        }
    }
}

private struct SettingsSheetView: View {
    @EnvironmentObject private var model: MacAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            LabeledContent("Control plane", value: AppConfig.current.baseURL.absoluteString)
            LabeledContent("Device ID", value: model.deviceId ?? "Not registered")
            LabeledContent("API key", value: model.apiKey == nil ? "Not stored" : "Stored in Keychain")
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private enum TaskListWindow {
    private static var window: NSWindow?

    @MainActor
    static func open(model: MacAppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = TaskListWindowView()
            .environmentObject(model)
        let hostingController = NSHostingController(rootView: content)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Gemma Tasks"
        newWindow.setContentSize(NSSize(width: 720, height: 560))
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }
}

private struct TaskListWindowView: View {
    @EnvironmentObject private var model: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tasks")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    _Concurrency.Task {
                        await model.refreshTasks()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }

            List(model.tasks) { task in
                TaskRowView(task: task)
                    .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
        .padding(16)
    }
}
