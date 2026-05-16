package com.gemma4all.mobilehost.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.gemma4all.mobilehost.ui.components.EventTimelineItem
import com.gemma4all.mobilehost.ui.viewmodels.TaskDetailViewModel
import com.gemma4all.mobilehost.ui.viewmodels.TaskResult

@Composable
fun TaskDetailScreen(
    taskId: String,
    onOpenApproval: () -> Unit,
    viewModel: TaskDetailViewModel = hiltViewModel()
) {
    val task by viewModel.task.collectAsState()
    val events by viewModel.events.collectAsState()
    val hasMoreEvents by viewModel.hasMoreEvents.collectAsState()
    val taskResult: TaskResult? by viewModel.taskResult.collectAsState()

    LaunchedEffect(taskId) {
        viewModel.load(taskId)
    }

    Column(modifier = Modifier.padding(16.dp)) {
        task?.let { currentTask ->
            Text("title: ${currentTask.taskTitle}")
            Text("state: ${currentTask.currentState}")
            Text("permission_level: ${currentTask.permissionLevel}")
            currentTask.currentRuntime?.let { runtime ->
                Text("runtime: $runtime")
            }
            if (currentTask.pendingApproval) {
                Spacer(modifier = Modifier.height(12.dp))
                Button(onClick = onOpenApproval) {
                    Text("打开审批")
                }
            }
        }
        taskResult?.let { result ->
            Spacer(modifier = Modifier.height(16.dp))
            androidx.compose.material3.Card(
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(12.dp)) {
                    Text(
                        text = "✓ 任务完成",
                        style = androidx.compose.material3.MaterialTheme.typography.titleMedium
                    )
                    if (result.summary.isNotBlank()) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(text = result.summary)
                    }
                    if (result.steps.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "执行步骤：",
                            style = androidx.compose.material3.MaterialTheme.typography.labelMedium
                        )
                        result.steps.forEach { step ->
                            Text(text = "  ${step.stepIndex}. ${step.toolName}")
                        }
                    }
                }
            }
        }
        Spacer(modifier = Modifier.height(16.dp))
        events.forEach { event ->
            EventTimelineItem(event = event)
        }
        if (hasMoreEvents) {
            Button(onClick = viewModel::loadMoreEvents) {
                Text("加载更多")
            }
        }
    }
}
