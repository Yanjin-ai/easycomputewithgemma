package com.gemma4all.mobilehost.services

import android.content.Context
import com.gemma4all.mobilehost.models.TaskDraft
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Singleton
class FunctionGemmaParserService @Inject constructor(
    @ApplicationContext private val context: Context,
    @Named("modelPath") private val modelPath: String
) : ParserRouterService {
    private val gson = Gson()
    @Volatile
    private var llmInference: LlmInference? = null

    override suspend fun parse(rawInput: String): TaskDraft {
        return try {
            withContext(Dispatchers.IO) {
                parseModelResponse(getLlmInference().generateResponse(buildPrompt(rawInput)))
            }
        } catch (_: Exception) {
            PlaceholderParserRouterService().parse(rawInput)
        }
    }

    private fun getLlmInference(): LlmInference {
        return llmInference ?: synchronized(this) {
            llmInference ?: LlmInference.createFromOptions(
                context,
                LlmInference.LlmInferenceOptions.builder()
                    .setModelPath(modelPath)
                    .setMaxTokens(512)
                    .setTopK(40)
                    .build()
            ).also { llmInference = it }
        }
    }

    private fun buildPrompt(rawInput: String): String {
        return """
            <start_of_turn>user
            [AVAILABLE_TOOLS] [{"type":"function","function":{"name":"create_task_draft","description":"Convert natural language task request to structured TaskDraft","parameters":{"type":"object","properties":{"intent":{"type":"string","description":"Short verb phrase describing the task goal"},"goal":{"type":"object","description":"Free-form key-value task details"},"required_tools":{"type":"array","items":{"type":"string"},"description":"Tool names needed, e.g. file_read, web_search"},"required_capabilities":{"type":"array","items":{"type":"string"},"description":"Capability names needed, e.g. internet_access"},"complexity_hint":{"type":"string","enum":["light","moderate","heavy"]},"permission_level":{"type":"string","enum":["local_only","private_lan","cloud_ok"]},"raw_input":{"type":"string","description":"Original user text verbatim"}},"required":["intent","goal","required_tools","required_capabilities","complexity_hint","permission_level","raw_input"]}}}] [/AVAILABLE_TOOLS]

            $rawInput<end_of_turn>
            <start_of_turn>model
        """.trimIndent()
    }

    private fun parseModelResponse(response: String): TaskDraft {
        val markerIndex = response.indexOf(TOOL_CALL_MARKER)
        require(markerIndex >= 0)

        val toolCallJson = response
            .substring(markerIndex + TOOL_CALL_MARKER.length)
            .trim()
            .lineSequence()
            .first()
        val toolCall = JsonParser.parseString(toolCallJson).asJsonObject
        require(toolCall["name"].asString == "create_task_draft")

        val arguments = toolCall["arguments"].asJsonObject
        return TaskDraft(
            schemaVersion = "1.0.0",
            intent = arguments["intent"].asString,
            goal = gson.fromJson(arguments["goal"], Map::class.java) as Map<String, Any>,
            requiredTools = arguments.getStringList("required_tools"),
            requiredCapabilities = arguments.getStringList("required_capabilities"),
            complexityHint = arguments["complexity_hint"].asString,
            permissionLevel = arguments["permission_level"].asString,
            rawInput = arguments["raw_input"].asString
        )
    }

    private fun JsonObject.getStringList(key: String): List<String> {
        return getAsJsonArray(key).map { it.asString }
    }

    private companion object {
        const val TOOL_CALL_MARKER = "[TOOL_CALL]"
    }
}
