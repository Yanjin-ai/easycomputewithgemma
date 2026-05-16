import SwiftUI

struct TaskRowView: View {
    let task: Task

    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.taskTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(task.createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(task.currentState)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(stateColor, in: Capsule())
            }
            .contentShape(Rectangle())
            .padding(8)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingDetail) {
            TaskDetailSheetView(taskId: task.taskId)
        }
    }

    private var stateColor: Color {
        switch task.currentState {
        case "running":
            return .blue
        case "completed":
            return .green
        case "failed":
            return .red
        default:
            return .gray
        }
    }
}

private struct TaskDetailSheetView: View {
    @EnvironmentObject private var model: MacAppModel
    @Environment(\.dismiss) private var dismiss

    let taskId: String

    @State private var task: Task?
    @State private var events: [Event] = []
    @State private var errorMessage: String?

    private var completedEvent: Event? {
        events.first { $0.eventType == "run.completed" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Task Detail")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            List {
                if let task {
                    Section("Task") {
                        LabeledContent("title", value: task.taskTitle)
                        LabeledContent("state", value: task.currentState)
                        LabeledContent("permission_level", value: task.permissionLevel)
                        if let currentRuntime = task.currentRuntime {
                            LabeledContent("runtime", value: currentRuntime)
                        }
                        LabeledContent("intent", value: task.intentSummary)
                        LabeledContent("complexity_hint", value: task.complexityHint)
                        LabeledContent("required_tools", value: task.requiredTools.joined(separator: ", "))
                        LabeledContent("required_capabilities", value: task.requiredCapabilities.joined(separator: ", "))
                    }
                } else {
                    ProgressView()
                }

                if let completedEvent {
                    Section("Result") {
                        ResultSummaryCard(event: completedEvent)
                    }
                }

                Section("Timeline") {
                    ForEach(events) { event in
                        EventTimelineRow(event: event)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(16)
        .frame(width: 620, height: 560)
        .task(id: taskId) {
            await pollUntilTerminal()
        }
    }

    private func pollUntilTerminal() async {
        while !_Concurrency.Task.isCancelled {
            await load()
            if task?.isTerminal == true {
                break
            }
            try? await _Concurrency.Task.sleep(for: .seconds(5))
        }
    }

    private func load() async {
        do {
            async let fetchedTask = model.client.getTask(taskId: taskId)
            async let fetchedEvents = model.client.getEvents(taskId: taskId, limit: 50)
            let (newTask, newEvents) = try await (fetchedTask, fetchedEvents.events)
            task = newTask
            events = newEvents
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ResultSummaryCard: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run completed")
                .font(.headline)

            ForEach(event.payload.sorted { $0.key < $1.key }, id: \.key) { key, value in
                LabeledContent(key, value: value.displayString)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct EventTimelineRow: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.eventType)
                .font(.headline)
            Text(event.recordedAt)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !event.payload.isEmpty {
                Text(event.payload.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value.displayString)" }
                    .joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
