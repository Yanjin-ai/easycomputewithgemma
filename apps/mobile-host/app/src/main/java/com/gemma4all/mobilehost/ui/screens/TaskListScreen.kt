package com.gemma4all.mobilehost.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.gemma4all.mobilehost.ui.components.TaskStatusChip
import com.gemma4all.mobilehost.ui.viewmodels.TaskListViewModel

@Composable
fun TaskListScreen(
    onTaskSelected: (String) -> Unit,
    viewModel: TaskListViewModel = hiltViewModel()
) {
    val tasks by viewModel.tasks.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    DisposableEffect(Unit) {
        viewModel.startPolling()
        onDispose { viewModel.stopPolling() }
    }

    Column(modifier = Modifier.padding(16.dp)) {
        Button(onClick = viewModel::refresh) {
            Text(if (isLoading) "刷新中" else "刷新")
        }
        tasks.forEach { task ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onTaskSelected(task.taskId) }
                    .padding(vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = task.taskTitle, modifier = Modifier.weight(1f))
                TaskStatusChip(taskState = task.currentState)
                if (task.pendingApproval) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("待审批")
                }
            }
        }
    }
}
