// MEDIAPIPE SETUP REQUIRED:
// In Xcode: File > Add Package Dependencies...
// URL: https://github.com/google-ai-edge/mediapipe-ios-release
// Version: Up to Next Major from 0.10.0
// Add product: MediaPipeTasksGenAI to GemmaHost target
//
// After adding, remove the #if canImport guard below and uncomment the import.

import Foundation

#if canImport(MediaPipeTasksGenAI)
import MediaPipeTasksGenAI
#endif

final class OnDeviceParserRouterService: ParserRouterService {
    private let modelManager: ModelManager

    #if canImport(MediaPipeTasksGenAI)
    private var inference: LlmInference?
    #endif

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func load() throws {
        #if canImport(MediaPipeTasksGenAI)
        guard let modelURL = modelManager.modelURL else {
            throw InferenceError.modelNotReady
        }

        var options = LlmInference.Options(modelPath: modelURL.path)
        options.maxTokens = 512
        options.topk = 40
        options.temperature = 0.1
        inference = try LlmInference(options: options)
        #else
        throw InferenceError.mediaPipeUnavailable
        #endif
    }

    func parse(rawInput: String, permissionLevel: String) async -> TaskDraft {
        #if canImport(MediaPipeTasksGenAI)
        guard let inference else {
            return await fallback(rawInput: rawInput, permissionLevel: permissionLevel)
        }

        let prompt = """
        You are a task parser. Given a user request, return ONLY a JSON object with no
        explanation. Format:
        {"intent":"brief intent summary","required_tools":["tool1"],"complexity_hint":"light or heavy"}

        Available tools: file_read, file_write, list_directory, run_shell_command, web_search

        Use complexity_hint="heavy" if the task needs file access or shell commands.
        Use complexity_hint="light" for simple queries or information tasks.

        User request: \(rawInput)

        JSON:
        """

        do {
            let response = try inference.generateResponse(inputText: prompt)
            return parseLLMResponse(response, rawInput: rawInput, permissionLevel: permissionLevel)
        } catch {
            return await fallback(rawInput: rawInput, permissionLevel: permissionLevel)
        }
        #else
        return await fallback(rawInput: rawInput, permissionLevel: permissionLevel)
        #endif
    }

    private func parseLLMResponse(_ text: String, rawInput: String, permissionLevel: String) -> TaskDraft {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return fallbackSync(rawInput: rawInput, permissionLevel: permissionLevel)
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallbackSync(rawInput: rawInput, permissionLevel: permissionLevel)
        }

        let intent = obj["intent"] as? String ?? rawInput
        let tools = obj["required_tools"] as? [String] ?? []
        let complexity = obj["complexity_hint"] as? String ?? "light"

        return TaskDraft(
            intent: intent,
            goal: ["description": .string(intent)],
            requiredTools: tools,
            requiredCapabilities: ["cpu_inference"],
            complexityHint: complexity,
            permissionLevel: permissionLevel,
            rawInput: rawInput,
            intentSummary: intent,
            taskTitle: String(intent.prefix(60))
        )
    }

    private func fallback(rawInput: String, permissionLevel: String) async -> TaskDraft {
        await StubParserRouterService().parse(rawInput: rawInput, permissionLevel: permissionLevel)
    }

    private func fallbackSync(rawInput: String, permissionLevel: String) -> TaskDraft {
        TaskDraft(
            intent: rawInput,
            goal: ["description": .string(rawInput)],
            requiredTools: [],
            requiredCapabilities: ["cpu_inference"],
            complexityHint: "light",
            permissionLevel: permissionLevel,
            rawInput: rawInput,
            intentSummary: rawInput,
            taskTitle: String(rawInput.prefix(60))
        )
    }

    enum InferenceError: Error {
        case modelNotReady
        case mediaPipeUnavailable
    }
}
