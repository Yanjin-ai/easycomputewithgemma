package com.gemma4all.mobilehost.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.gemma4all.mobilehost.client.ControlPlaneApi
import com.gemma4all.mobilehost.models.Task
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class TaskListViewModel @Inject constructor(
    private val controlPlaneApi: ControlPlaneApi
) : ViewModel() {
    private val _tasks = MutableStateFlow<List<Task>>(emptyList())
    val tasks: StateFlow<List<Task>> = _tasks.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private var pollingJob: Job? = null

    fun refresh() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching {
                controlPlaneApi.listTasks()
            }.onSuccess { response ->
                _tasks.value = response.tasks
            }
            _isLoading.value = false
        }
    }

    fun startPolling() {
        stopPolling()
        pollingJob = viewModelScope.launch {
            while (isActive) {
                refresh()
                delay(10_000)
            }
        }
    }

    fun stopPolling() {
        pollingJob?.cancel()
        pollingJob = null
    }

    override fun onCleared() {
        stopPolling()
        super.onCleared()
    }
}
