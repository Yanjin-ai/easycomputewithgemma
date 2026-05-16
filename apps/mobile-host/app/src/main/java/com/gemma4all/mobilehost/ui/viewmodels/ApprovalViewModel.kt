package com.gemma4all.mobilehost.ui.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.gemma4all.mobilehost.client.ControlPlaneApi
import com.gemma4all.mobilehost.models.Approval
import com.gemma4all.mobilehost.models.ApprovalResponse
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ApprovalViewModel @Inject constructor(
    private val controlPlaneApi: ControlPlaneApi
) : ViewModel() {
    private val _approval = MutableStateFlow<Approval?>(null)
    val approval: StateFlow<Approval?> = _approval.asStateFlow()

    fun load(approvalId: String) {
        viewModelScope.launch {
            runCatching {
                controlPlaneApi.getApproval(approvalId)
            }.onSuccess { loadedApproval ->
                _approval.value = loadedApproval
            }
        }
    }

    fun approve(note: String?) {
        val approvalId = _approval.value?.approvalId ?: return
        viewModelScope.launch {
            runCatching {
                controlPlaneApi.respondApproval(
                    approvalId = approvalId,
                    response = ApprovalResponse(
                        response = "approved",
                        responseNote = note
                    )
                )
            }.onSuccess { updatedApproval ->
                _approval.value = updatedApproval
            }
        }
    }

    fun reject(reason: String) {
        val approvalId = _approval.value?.approvalId ?: return
        viewModelScope.launch {
            runCatching {
                controlPlaneApi.respondApproval(
                    approvalId = approvalId,
                    response = ApprovalResponse(
                        response = "rejected",
                        responseNote = reason
                    )
                )
            }.onSuccess { updatedApproval ->
                _approval.value = updatedApproval
            }
        }
    }
}
