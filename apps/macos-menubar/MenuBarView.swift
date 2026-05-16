import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.tasks.prefix(10)) { task in
                    TaskRow(task: task)
                }

                if model.tasks.isEmpty {
                    Text(model.isLoading ? "Loading..." : "No tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button {
                Task {
                    await model.refreshTasks()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("r")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 360, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Text("Recent Tasks")
                .font(.headline)
            Spacer()
            if model.isLoading {
                ProgressView()
                    .scaleEffect(0.55)
            }
        }
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var model: MenuBarModel

    let task: GemmaTask

    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.statusIcon)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displaySummary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(task.currentState)
                        if !task.createdAt.isEmpty {
                            Text(relativeTime(from: task.createdAt))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.body)
        .popover(isPresented: $isShowingDetail, arrowEdge: .trailing) {
            TaskDetailPopover(task: task)
                .environmentObject(model)
        }
    }

    private func relativeTime(from dateString: String) -> String {
        guard let date = ISO8601DateFormatter.gemma.date(from: dateString) else {
            return ""
        }

        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "刚刚"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分钟前"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours) 小时前"
        }

        let days = hours / 24
        return "\(days) 天前"
    }
}

private struct TaskDetailPopover: View {
    @EnvironmentObject private var model: MenuBarModel

    let task: GemmaTask

    @State private var detailTask: GemmaTask?
    @State private var events: [TaskEvent] = []
    @State private var errorMessage: String?

    private var currentTask: GemmaTask {
        detailTask ?? task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentTask.taskTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("state", value: currentTask.currentState)
                LabeledContent("intent", value: currentTask.intentSummary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Events")
                    .font(.subheadline.weight(.semibold))
                if events.isEmpty && errorMessage == nil {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(events.prefix(5)) { event in
                        EventRow(event: event)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .topLeading)
        .task(id: task.taskId) {
            await loadDetails()
        }
    }

    private func loadDetails() async {
        do {
            let (task, events) = try await model.taskDetails(taskId: task.taskId)
            detailTask = task
            self.events = Array(events.prefix(5))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EventRow: View {
    let event: TaskEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.eventType)
                .font(.caption.weight(.semibold))
            if !event.payload.isEmpty {
                Text(event.payload.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value.displayString)" }
                    .joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ISO8601DateFormatter {
    static let gemma: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
