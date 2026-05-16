package com.gemma4all.mobilehost.services

import com.gemma4all.mobilehost.models.TaskDraft
import javax.inject.Inject

interface ParserRouterService {
    suspend fun parse(rawInput: String): TaskDraft
}

class PlaceholderParserRouterService @Inject constructor() : ParserRouterService {
    override suspend fun parse(rawInput: String): TaskDraft {
        return TaskDraft(
            schemaVersion = "1.0.0",
            intent = "general_task",
            goal = mapOf("description" to rawInput),
            requiredTools = emptyList(),
            requiredCapabilities = emptyList(),
            complexityHint = "light",
            permissionLevel = "private_lan",
            rawInput = rawInput
        )
    }
}
