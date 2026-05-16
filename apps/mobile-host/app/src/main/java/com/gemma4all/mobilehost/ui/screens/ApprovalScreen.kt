package com.gemma4all.mobilehost.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.gemma4all.mobilehost.ui.viewmodels.ApprovalViewModel

@Composable
fun ApprovalScreen(
    approvalId: String,
    viewModel: ApprovalViewModel = hiltViewModel()
) {
    val approval by viewModel.approval.collectAsState()
    var showRejectDialog by remember { mutableStateOf(false) }
    var rejectReason by remember { mutableStateOf("") }

    LaunchedEffect(approvalId) {
        viewModel.load(approvalId)
    }

    Column(modifier = Modifier.padding(16.dp)) {
        approval?.let { currentApproval ->
            Text(currentApproval.actionDescription)
            Text("expires_at: ${currentApproval.expiresAt}")
            Spacer(modifier = Modifier.height(16.dp))
            Row {
                Button(onClick = { viewModel.approve(note = null) }) {
                    Text("批准")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(onClick = { showRejectDialog = true }) {
                    Text("拒绝")
                }
            }
        }
    }

    if (showRejectDialog) {
        AlertDialog(
            onDismissRequest = { showRejectDialog = false },
            title = { Text("拒绝原因") },
            text = {
                OutlinedTextField(
                    value = rejectReason,
                    onValueChange = { rejectReason = it }
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.reject(rejectReason)
                        showRejectDialog = false
                    }
                ) {
                    Text("提交")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRejectDialog = false }) {
                    Text("取消")
                }
            }
        )
    }
}
