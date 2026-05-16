package com.gemma4all.mobilehost.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.gemma4all.mobilehost.models.Event

@Composable
fun EventTimelineItem(
    event: Event,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
    ) {
        Text(text = event.eventType, style = MaterialTheme.typography.titleSmall)
        Text(text = event.source, style = MaterialTheme.typography.bodySmall)
        Text(text = event.emittedAt, style = MaterialTheme.typography.bodySmall)
    }
}
