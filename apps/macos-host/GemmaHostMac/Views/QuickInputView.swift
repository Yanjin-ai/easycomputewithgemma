import SwiftUI

struct QuickInputView: View {
    @EnvironmentObject private var model: MacAppModel

    @State private var input = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Describe a task…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submit()
                    }

                Button(isSubmitting ? "Submitting" : "Submit") {
                    submit()
                }
                .disabled(!canSubmit)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        let rawInput = input
        isSubmitting = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                try await model.submitQuickTask(rawInput: rawInput)
                input = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
