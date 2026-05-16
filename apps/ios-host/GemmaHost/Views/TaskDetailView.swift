import SwiftUI
import UIKit

struct TaskDetailView: View {
    @EnvironmentObject private var model: AppModel

    let taskId: String

    @State private var task: Task?
    @State private var events: [TaskEvent] = []
    @State private var didFetchCompletionEvents = false
    @State private var isLoadingCompletionEvents = false
    @State private var errorMessage: String?
    @State private var confirmation: TaskActionConfirmation?
    @State private var isActionInFlight = false
    @State private var pollGeneration = 0

    private var completedEvent: TaskEvent? {
        events
            .filter { $0.eventType == "run.completed" }
            .max { $0.emittedAt < $1.emittedAt }
    }

    private var canCancelTask: Bool {
        guard let task else { return false }
        return ["pending", "routing", "scheduled", "running", "paused"].contains(task.currentState)
    }

    private var canRetryTask: Bool {
        task?.currentState == "failed"
    }

    private var completionSummary: String? {
        if case .string(let summary) = completedEvent?.payload["summary"] {
            let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedSummary.isEmpty ? nil : trimmedSummary
        }

        return task?.completionSummary
    }

    private var displayedCompletionSummary: String? {
        if isLoadingCompletionEvents,
           let outputSummary = task?.outputSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputSummary.isEmpty {
            return outputSummary
        }

        return completionSummary
    }

    var body: some View {
        List {
            if let task {
                Section("Task") {
                    LabeledContent("title", value: task.taskTitle)
                    LabeledContent("state") {
                        HStack(spacing: 6) {
                            TaskStateBadge(state: task.currentState)
                            if task.currentState == "queued" {
                                if let position = task.queuePosition {
                                    Text("（第 \(position) 个）")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("（等待中）")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let createdAt = formattedTaskTime(task.createdAt) {
                        LabeledContent("submitted", value: createdAt)
                    }
                    if let lastUpdatedAt = formattedTaskTime(task.lastUpdatedAt) {
                        LabeledContent("last updated", value: lastUpdatedAt)
                    }
                    LabeledContent("run count", value: String(task.totalRunCount))
                    if task.currentState == "completed" {
                        CompletionSummaryView(
                            summary: displayedCompletionSummary,
                            isLoading: isLoadingCompletionEvents && displayedCompletionSummary == nil
                        )
                    }
                    LabeledContent("permission_level", value: task.permissionLevel)
                    if let currentRuntime = task.currentRuntime {
                        LabeledContent("runtime", value: currentRuntime)
                    }
                    LabeledContent("intent", value: task.intentSummary)
                    LabeledContent("complexity_hint", value: task.complexityHint)
                    LabeledContent("required_tools", value: task.requiredTools.joined(separator: ", "))
                    LabeledContent("required_capabilities", value: task.requiredCapabilities.joined(separator: ", "))
                }

                if canCancelTask || canRetryTask {
                    Section("Actions") {
                        if canCancelTask {
                            Button(role: .destructive) {
                                confirmation = .cancel
                            } label: {
                                Text("Cancel Task")
                            }
                            .disabled(isActionInFlight)
                        }

                        if canRetryTask {
                            Button {
                                confirmation = .retry
                            } label: {
                                Text("Retry")
                            }
                            .disabled(isActionInFlight)
                        }
                    }
                }
            } else {
                ProgressView()
            }

            if !events.isEmpty {
                Section("Timeline") {
                    ForEach(events.sorted { $0.emittedAt < $1.emittedAt }) { event in
                        EventTimelineRow(event: event)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Task Detail")
        .alert(item: $confirmation) { confirmation in
            Alert(
                title: Text(confirmation.title),
                message: Text(confirmation.message),
                primaryButton: .cancel(),
                secondaryButton: confirmationButton(for: confirmation)
            )
        }
        .task(id: pollGeneration) {
            await pollUntilTerminal()
        }
    }

    private func pollUntilTerminal() async {
        didFetchCompletionEvents = false
        events = []

        do {
            for try await updatedTask in model.client.streamTaskUpdates(taskId: taskId) {
                task = updatedTask
                model.handleStreamedTaskUpdate(updatedTask)
                await loadEvents()
                if updatedTask.currentState == "completed" {
                    await loadCompletionEventsIfNeeded()
                }
                if updatedTask.isTerminal { return }
            }
            return
        } catch {
            errorMessage = nil
        }

        while !_Concurrency.Task.isCancelled {
            await loadTask()
            await loadEvents()
            if task?.isTerminal == true {
                break
            }
            try? await _Concurrency.Task.sleep(for: .seconds(5))
        }
    }

    private func loadTask() async {
        do {
            task = try await model.client.getTask(taskId: taskId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadEvents() async {
        do {
            events = try await model.client.fetchEvents(taskId: taskId, limit: 50)
            model.updateTaskCompletionSummary(taskId: taskId, summary: completionSummary)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCompletionEventsIfNeeded() async {
        guard !didFetchCompletionEvents else { return }
        didFetchCompletionEvents = true
        isLoadingCompletionEvents = true
        defer { isLoadingCompletionEvents = false }

        await loadEvents()
    }

    private func performTaskAction(_ kind: TaskActionKind) async {
        isActionInFlight = true
        defer { isActionInFlight = false }

        do {
            switch kind {
            case .cancel:
                try await model.client.cancelTask(taskId: taskId)
            case .retry:
                try await model.client.retryTask(taskId: taskId)
                pollGeneration += 1
            }
            await loadTask()
            await loadEvents()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmationButton(for confirmation: TaskActionConfirmation) -> Alert.Button {
        switch confirmation.kind {
        case .cancel:
            return .destructive(Text(confirmation.confirmTitle)) {
                _Concurrency.Task {
                    await performTaskAction(confirmation.kind)
                }
            }
        case .retry:
            return .default(Text(confirmation.confirmTitle)) {
                _Concurrency.Task {
                    await performTaskAction(confirmation.kind)
                }
            }
        }
    }

    private func formattedTaskTime(_ timestamp: String) -> String? {
        let trimmedTimestamp = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTimestamp.isEmpty else { return nil }

        guard let date = Self.iso8601Formatter.date(from: trimmedTimestamp)
            ?? Self.iso8601NoFractionFormatter.date(from: trimmedTimestamp) else {
            return trimmedTimestamp
        }
        return Self.taskTimeFormatter.string(from: date)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601NoFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let taskTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private enum TaskActionKind {
    case cancel
    case retry
}

private struct TaskActionConfirmation: Identifiable {
    let kind: TaskActionKind
    let title: String
    let message: String
    let confirmTitle: String

    var id: String { confirmTitle }

    static let cancel = TaskActionConfirmation(
        kind: .cancel,
        title: "Cancel Task?",
        message: "This will request cancellation for the current task.",
        confirmTitle: "Cancel Task"
    )

    static let retry = TaskActionConfirmation(
        kind: .retry,
        title: "Retry Task?",
        message: "This will request another attempt for the failed task.",
        confirmTitle: "Retry"
    )
}

private struct TaskStateBadge: View {
    let state: String

    var body: some View {
        let display = TaskStateDisplay.from(state)
        HStack(spacing: 4) {
            Text(display.icon)
            Text(state)
                .foregroundStyle(display.color)
        }
        .font(.subheadline.weight(.semibold))
    }
}

private struct CompletionSummaryView: View {
    let summary: String?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            if isLoading {
                ProgressView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button {
                            UIPasteboard.general.string = summary
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .disabled(summary == nil)
                    }

                    ScrollView {
                        Text(summary ?? "任务已完成，无摘要")
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 80, maxHeight: 220)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct EventTimelineRow: View {
    let event: TaskEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.eventType)
                    .font(.headline)
                Spacer()
                Text(event.formattedEmittedAt)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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

private extension TaskEvent {
    var formattedEmittedAt: String {
        guard let date = Self.iso8601Formatter.date(from: emittedAt)
            ?? Self.iso8601NoFractionFormatter.date(from: emittedAt) else {
            return emittedAt
        }
        return Self.timelineTimeFormatter.string(from: date)
    }

    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601NoFractionFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let timelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
