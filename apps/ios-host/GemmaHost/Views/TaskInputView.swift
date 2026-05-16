import SwiftUI
import UIKit

struct TaskInputView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechInputController()

    @State private var rawInput = ""
    @State private var permissionLevel = "private_lan"
    @State private var parsedDraft: TaskDraft?
    @State private var navigationPath: [String] = []
    @State private var errorMessage: String?
    @State private var isParsing = false
    @State private var isSubmitting = false

    private var trimmedInput: String {
        rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedInput.isEmpty && rawInput.count <= 500 && !isSubmitting
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                Section("Task") {
                    HStack(alignment: .top, spacing: 10) {
                        TextField("Describe a task", text: $rawInput, axis: .vertical)
                            .lineLimit(2...4)

                        Button {
                            speech.toggle { text in
                                rawInput = text
                            }
                        } label: {
                            Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(speech.isListening ? "Stop voice input" : "Start voice input")
                    }

                    Text("\(rawInput.count) / 500 chars")
                        .font(.caption)
                        .foregroundStyle(rawInput.count > 500 ? .red : .secondary)

                    PermissionPicker(permissionLevel: $permissionLevel)
                }

                Section {
                    Button(action: submit) {
                        Label(isSubmitting ? "Submitting…" : "Submit Task", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)

                    if isSubmitting {
                        ProgressView()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if model.modelManager.isOnDeviceInferenceAvailable {
                    switch model.modelManager.state {
                    case .notDownloaded:
                        Section {
                            Text("Model not ready — download required")
                                .foregroundStyle(.secondary)

                            Button("Download") {
                                downloadModel()
                            }
                        }

                    case .downloading(let progress):
                        Section {
                            ProgressView(value: progress) {
                                Text("Downloading model…")
                            }
                        }

                    case .ready:
                        Section {
                            Button(isParsing ? "Parsing..." : "Parse") {
                                parse()
                            }
                            .disabled(rawInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                        }

                    case .failed(let message):
                        Section {
                            Text(message)
                                .foregroundStyle(.red)

                            Button("Download") {
                                downloadModel()
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Tasks run on your Mac via the Gemma desktop runtime.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let parsedDraft {
                    Section("Parsed") {
                        LabeledContent("intent", value: parsedDraft.intent)
                        LabeledContent("required_tools", value: parsedDraft.requiredTools.joined(separator: ", "))
                        LabeledContent("complexity_hint", value: parsedDraft.complexityHint)
                    }
                }

                if let authorizationError = speech.authorizationError {
                    Section {
                        Text(authorizationError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                hideKeyboard()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationDestination(for: String.self) { taskId in
                TaskDetailView(taskId: taskId)
            }
        }
    }

    private func parse() {
        isParsing = true
        errorMessage = nil
        _Concurrency.Task {
            let draft = await model.parser.parse(rawInput: rawInput, permissionLevel: permissionLevel)
            await MainActor.run {
                parsedDraft = draft
                isParsing = false
            }
        }
    }

    private func downloadModel() {
        _Concurrency.Task {
            await model.modelManager.download()
            model.loadOnDeviceParserIfReady()
        }
    }

    private func submit() {
        guard canSubmit else { return }
        hideKeyboard()
        let text = rawInput
        isSubmitting = true
        errorMessage = nil
        _Concurrency.Task {
            do {
                _ = try await model.submitTask(text: text)
                await model.refreshTasks()
                await MainActor.run {
                    rawInput = ""
                    parsedDraft = nil
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
