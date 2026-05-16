import Foundation

protocol ParserRouterService {
    func parse(rawInput: String, permissionLevel: String) async -> TaskDraft
}

extension ParserRouterService {
    func parse(text: String) async -> TaskDraft {
        await parse(rawInput: text, permissionLevel: "private_lan")
    }
}

struct StubParserRouterService: ParserRouterService {
    func parse(rawInput: String, permissionLevel: String) async -> TaskDraft {
        let title = String(rawInput.prefix(60))

        // complexityHint must be "light" | "medium" | "heavy" per common.schema.json
        return TaskDraft(
            intent: rawInput,
            goal: ["description": .string(rawInput)],
            requiredTools: [],
            requiredCapabilities: ["cpu_inference"],  // requires a runtime with Gemma weights; mobile sends [] so it never qualifies
            complexityHint: "light",
            permissionLevel: "private_lan",
            rawInput: rawInput,
            intentSummary: rawInput,
            taskTitle: title
        )
    }
}
