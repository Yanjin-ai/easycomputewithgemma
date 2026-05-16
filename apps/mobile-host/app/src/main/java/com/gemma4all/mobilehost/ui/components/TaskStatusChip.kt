package com.gemma4all.mobilehost.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun TaskStatusChip(
    taskState: String,
    modifier: Modifier = Modifier
) {
    val (label, color) = taskStatusPresentation(taskState)
    Box(
        modifier = modifier
            .background(color = color, shape = RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp)
    ) {
        Text(text = label, style = MaterialTheme.typography.labelSmall)
    }
}

fun taskStatusPresentation(taskState: String): Pair<String, Color> {
    return when (taskState) {
        "draft" -> "草稿" to Color(0xFFE0E0E0)
        "pending" -> "待处理" to Color(0xFFFFF3CD)
        "routing" -> "路由中" to Color(0xFFD7E8FF)
        "scheduled" -> "已调度" to Color(0xFFDDEBFF)
        "running" -> "运行中" to Color(0xFFD9F7E8)
        "paused" -> "已暂停" to Color(0xFFFFE0B2)
        "completed" -> "已完成" to Color(0xFFC8E6C9)
        "failed" -> "失败" to Color(0xFFFFCDD2)
        "cancelled" -> "已取消" to Color(0xFFE0E0E0)
        else -> taskState to Color(0xFFE0E0E0)
    }
}
