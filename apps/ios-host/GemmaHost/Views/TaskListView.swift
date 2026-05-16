import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingSettings = false
    @State private var isShowingClearHistoryAlert = false

    private let activeStates = ["running", "paused", "routing", "scheduled"]
    private let pendingStates = ["pending"]
    private let historicalStates = ["completed", "failed", "cancelled"]

    private var activeTasks: [Task] {
        model.tasks.filter { activeStates.contains($0.currentState) }
    }

    private var pendingTasks: [Task] {
        model.tasks.filter { pendingStates.contains($0.currentState) }
    }

    private var completedTasks: [Task] {
        newestFirst(model.tasks.filter { $0.currentState == "completed" })
            .prefix(10)
            .map { $0 }
    }

    private var failedOrCancelledTasks: [Task] {
        newestFirst(model.tasks.filter { ["failed", "cancelled"].contains($0.currentState) })
            .prefix(10)
            .map { $0 }
    }

    private var activeCount: Int {
        model.tasks.filter { (activeStates + pendingStates).contains($0.currentState) }.count
    }

    private var hasHistoricalTasks: Bool {
        model.tasks.contains { historicalStates.contains($0.currentState) }
    }

    private func newestFirst(_ tasks: [Task]) -> [Task] {
        tasks.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if let listError = model.listError {
                Section {
                    Text(listError)
                        .foregroundStyle(.orange)
                }
            }

            if model.isLoadingTasks && model.tasks.isEmpty {
                ProgressView()
            }

            if !activeTasks.isEmpty {
                Section("Active") {
                    ForEach(activeTasks) { task in
                        taskRow(task)
                    }
                }
            }

            if !pendingTasks.isEmpty {
                Section("Pending") {
                    ForEach(pendingTasks) { task in
                        taskRow(task)
                    }
                }
            }

            if !completedTasks.isEmpty {
                Section("Completed") {
                    ForEach(completedTasks) { task in
                        taskRow(task)
                    }
                }
            }

            if !failedOrCancelledTasks.isEmpty {
                Section("Failed / Cancelled") {
                    ForEach(failedOrCancelledTasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
        .navigationTitle(activeCount > 0 ? "Tasks (\(activeCount) active)" : "Tasks")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if hasHistoricalTasks {
                    Button("Clear History") {
                        isShowingClearHistoryAlert = true
                    }
                    .accessibilityLabel("Clear task history")
                }

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")

                Button {
                    _Concurrency.Task {
                        await model.refreshTasks()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh tasks")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .alert("Remove completed and failed tasks from view?", isPresented: $isShowingClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                model.tasks = model.tasks.filter {
                    ["running", "paused", "routing", "scheduled", "pending"].contains($0.currentState)
                }
            }
        }
        .refreshable {
            await model.refreshTasks()
        }
        .task {
            while !_Concurrency.Task.isCancelled {
                await model.refreshTasks()

                do {
                    try await _Concurrency.Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
            }
        }
    }

    private func taskRow(_ task: Task) -> some View {
        NavigationLink {
            TaskDetailView(taskId: task.taskId)
        } label: {
            let display = TaskStateDisplay.from(task.currentState)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.taskTitle)
                    .font(.headline)
                    .lineLimit(2)
                if let summaryPreview = outputSummaryPreview(for: task) {
                    Text(summaryPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    statusIcon(display.icon, isPending: task.currentState == "pending")
                        .font(.subheadline)
                    Text(task.currentState)
                        .font(.subheadline)
                        .foregroundStyle(display.color)
                    Spacer()
                    Text(task.createdAt.prefix(10))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func outputSummaryPreview(for task: Task) -> String? {
        guard task.currentState == "completed",
              let summary = task.outputSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return nil
        }

        return String(summary.prefix(80))
    }

    @ViewBuilder
    private func statusIcon(_ icon: String, isPending: Bool) -> some View {
        if isPending {
            if #available(iOS 17.0, *) {
                Text(icon)
                    .symbolEffect(.pulse)
            } else {
                Text(icon)
            }
        } else {
            Text(icon)
        }
    }
}
