import AppIntents
import Foundation

struct GemmaSubmitTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Submit Gemma Task"
    static let description = IntentDescription(
        "Submit a task to Gemma4all running on your Mac.",
        categoryName: "Productivity"
    )

    @Parameter(title: "Task", description: "What should Gemma4all do?")
    var taskText: String

    @Parameter(title: "Wait for result", default: true)
    var waitForResult: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Gemma4all to \(\.$taskText)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let client = IntentControlPlaneClient()

        do {
            let submittedTask = try await client.submitTask(text: taskText)

            let resultSummary: String
            if waitForResult {
                resultSummary = try await waitForTaskResult(
                    taskId: submittedTask.taskId,
                    initialTask: submittedTask,
                    client: client
                )
            } else {
                resultSummary = "Task submitted. Check the Gemma4all app for results."
            }

            return .result(
                value: resultSummary,
                dialog: IntentDialog(stringLiteral: resultSummary)
            )
        } catch let error as IntentError {
            throw error
        } catch let error as IntentControlPlaneError {
            switch error {
            case .notReachable:
                throw IntentError.noMacConnection
            case .httpStatus(_, let message):
                throw IntentError.taskFailed(message ?? error.localizedDescription)
            default:
                throw IntentError.taskFailed(error.localizedDescription)
            }
        } catch {
            throw IntentError.taskFailed(error.localizedDescription)
        }
    }

    private func waitForTaskResult(
        taskId: String,
        initialTask: Task,
        client: IntentControlPlaneClient
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask {
                try await pollTaskResult(
                    taskId: taskId,
                    initialTask: initialTask,
                    client: client
                )
            }

            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: 60_000_000_000)
                return nil
            }

            let result = try await group.next() ?? nil
            group.cancelAll()

            return result ?? "Task is still running. Check the Gemma4all app."
        }
    }

    private func pollTaskResult(
        taskId: String,
        initialTask: Task,
        client: IntentControlPlaneClient
    ) async throws -> String {
        var task = initialTask

        while !_Concurrency.Task.isCancelled {
            if task.isTerminal {
                return try summary(for: task)
            }

            try await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
            task = try await client.getTask(taskId: taskId)
        }

        return "Task is still running. Check the Gemma4all app."
    }

    private func summary(for task: Task) throws -> String {
        if task.currentState == "failed" || task.currentState == "cancelled" {
            throw IntentError.taskFailed(task.outputSummary ?? task.completionSummary ?? task.currentState)
        }

        return task.outputSummary
            ?? task.completionSummary
            ?? task.intentSummary
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noMacConnection
    case taskFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noMacConnection:
            return "Cannot reach your Mac. Make sure Gemma4all is running."
        case .taskFailed(let msg):
            return "Task failed: \(msg)"
        }
    }
}
