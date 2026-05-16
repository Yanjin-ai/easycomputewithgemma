package com.gemma4all.mobilehost.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.gemma4all.mobilehost.client.ControlPlaneApi
import com.gemma4all.mobilehost.models.Event
import com.gemma4all.mobilehost.models.Task
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

private val TERMINAL_STATES = setOf("completed", "failed", "cancelled")

@HiltViewModel
class TaskDetailViewModel @Inject constructor(
    private val controlPlaneApi: ControlPlaneApi
) : ViewModel() {
    private val _task = MutableStateFlow<Task?>(null)
    val task: StateFlow<Task?> = _task.asStateFlow()

    private val _events = MutableStateFlow<List<Event>>(emptyList())
    val events: StateFlow<List<Event>> = _events.asStateFlow()

    private val _hasMoreEvents = MutableStateFlow(false)
    val hasMoreEvents: StateFlow<Boolean> = _hasMoreEvents.asStateFlow()

    private val _taskResult = MutableStateFlow<TaskResult?>(null)
    val taskResult: StateFlow<TaskResult?> = _taskResult.asStateFlow()

    private var taskId: String? = null
    private var nextCursor: String? = null
    private var pollingJob: kotlinx.coroutines.Job? = null

    fun load(taskId: String) {
        this.taskId = taskId
        viewModelScope.launch { fetchAll(taskId) }
        startPolling(taskId)
    }

    private suspend fun fetchAll(taskId: String) {
        runCatching {
            controlPlaneApi.getTask(taskId)
        }.onSuccess { loadedTask ->
            _task.value = loadedTask
        }

        runCatching {
            controlPlaneApi.getEvents(taskId = taskId)
        }.onSuccess { response ->
            _events.value = response.events
            nextCursor = response.nextCursor
            _hasMoreEvents.value = response.nextCursor != null

            val allEvents = _events.value
            val completedEvent = allEvents.lastOrNull { it.eventType == "run.completed" }
            if (completedEvent != null) {
                val summary = completedEvent.payload["summary"] as? String ?: ""
                val steps = allEvents
                    .filter { it.eventType == "run.step_completed" }
                    .mapNotNull { event ->
                        val stepIndex = (event.payload["step_index"] as? Double)?.toInt()
                            ?: return@mapNotNull null
                        val toolName = event.payload["tool"] as? String
                            ?: return@mapNotNull null
                        StepRecord(stepIndex, toolName)
                    }
                    .sortedBy { it.stepIndex }
                _taskResult.value = TaskResult(summary, steps)
            }
        }
    }

    private fun startPolling(taskId: String) {
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            while (true) {
                kotlinx.coroutines.delay(5_000)
                fetchAll(taskId)
                val state = _task.value?.currentState
                if (state != null && state in TERMINAL_STATES) break
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        pollingJob?.cancel()
    }

    fun loadMoreEvents() {
        val currentTaskId = taskId ?: return
        val cursor = nextCursor ?: return
        viewModelScope.launch {
            runCatching {
                controlPlaneApi.getEvents(taskId = currentTaskId, before = cursor)
            }.onSuccess { response ->
                _events.value = _events.value + response.events
                nextCursor = response.nextCursor
                _hasMoreEvents.value = response.nextCursor != null
            }
        }
    }
}

data class TaskResult(
    val summary: String,
    val steps: List<StepRecord>,
)

data class StepRecord(
    val stepIndex: Int,
    val toolName: String,
)
