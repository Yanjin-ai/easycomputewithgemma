package com.gemma4all.mobilehost.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.gemma4all.mobilehost.client.ControlPlaneApi
import com.gemma4all.mobilehost.models.Task
import com.gemma4all.mobilehost.models.TaskDraft
import com.gemma4all.mobilehost.services.ParserRouterService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed interface SubmissionState {
    data object Idle : SubmissionState
    data object Parsing : SubmissionState
    data object Submitting : SubmissionState
    data class Success(val task: Task) : SubmissionState
    data class Error(val message: String) : SubmissionState
}

@HiltViewModel
class TaskInputViewModel @Inject constructor(
    private val parserRouterService: ParserRouterService,
    private val controlPlaneApi: ControlPlaneApi
) : ViewModel() {
    private val _inputText = MutableStateFlow("")
    val inputText: StateFlow<String> = _inputText.asStateFlow()

    private val _parsedDraft = MutableStateFlow<TaskDraft?>(null)
    val parsedDraft: StateFlow<TaskDraft?> = _parsedDraft.asStateFlow()

    private val _selectedPermissionLevel = MutableStateFlow<String?>(null)
    val selectedPermissionLevel: StateFlow<String?> = _selectedPermissionLevel.asStateFlow()

    private val _submissionState = MutableStateFlow<SubmissionState>(SubmissionState.Idle)
    val submissionState: StateFlow<SubmissionState> = _submissionState.asStateFlow()

    fun onInputChanged(text: String) {
        _inputText.value = text
    }

    fun onVoiceResult(text: String) {
        _inputText.value = text
        onParseRequested()
    }

    fun onPermissionLevelSelected(permissionLevel: String) {
        _selectedPermissionLevel.value = permissionLevel
    }

    fun onParseRequested() {
        viewModelScope.launch {
            _submissionState.value = SubmissionState.Parsing
            runCatching {
                parserRouterService.parse(_inputText.value)
            }.onSuccess { draft ->
                _parsedDraft.value = draft
                _submissionState.value = SubmissionState.Idle
            }.onFailure { error ->
                _submissionState.value = SubmissionState.Error(error.message ?: "Parse failed")
            }
        }
    }

    fun onSubmitConfirmed() {
        viewModelScope.launch {
            val draft = _parsedDraft.value
            val permissionLevel = _selectedPermissionLevel.value
            if (draft == null) {
                _submissionState.value = SubmissionState.Error("Parse the task before submitting")
                return@launch
            }
            if (permissionLevel == null) {
                _submissionState.value = SubmissionState.Error("Choose a permission level before submitting")
                return@launch
            }

            _submissionState.value = SubmissionState.Submitting
            runCatching {
                controlPlaneApi.submitTask(draft.copy(permissionLevel = permissionLevel))
            }.onSuccess { task ->
                _submissionState.value = SubmissionState.Success(task)
            }.onFailure { error ->
                _submissionState.value = SubmissionState.Error(error.message ?: "Submit failed")
            }
        }
    }
}
