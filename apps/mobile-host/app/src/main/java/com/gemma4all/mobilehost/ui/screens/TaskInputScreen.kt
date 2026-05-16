package com.gemma4all.mobilehost.ui.screens

import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.gemma4all.mobilehost.ui.viewmodels.TaskInputViewModel

@Composable
fun TaskInputScreen(
    viewModel: TaskInputViewModel = hiltViewModel()
) {
    val inputText by viewModel.inputText.collectAsState()
    val parsedDraft by viewModel.parsedDraft.collectAsState()
    val selectedPermissionLevel by viewModel.selectedPermissionLevel.collectAsState()

    Column(modifier = Modifier.padding(16.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = inputText,
                onValueChange = viewModel::onInputChanged,
                modifier = Modifier.weight(1f),
                label = { Text("任务输入") }
            )
            // Note: RECORD_AUDIO runtime permission must be granted before use.
            // A permission request screen should be added in a future iteration.
            VoiceInputButton(onResult = viewModel::onVoiceResult)
        }
        Spacer(modifier = Modifier.height(12.dp))
        Button(onClick = viewModel::onParseRequested) {
            Text("解析")
        }
        Spacer(modifier = Modifier.height(12.dp))
        parsedDraft?.let { draft ->
            Text("intent: ${draft.intent}")
            Text("required_tools: ${draft.requiredTools.joinToString()}")
            Text("complexity_hint: ${draft.complexityHint}")
        }
        Spacer(modifier = Modifier.height(12.dp))
        PermissionLevelSelector(
            selectedPermissionLevel = selectedPermissionLevel,
            onPermissionLevelSelected = viewModel::onPermissionLevelSelected
        )
        Spacer(modifier = Modifier.height(12.dp))
        Button(onClick = viewModel::onSubmitConfirmed) {
            Text("提交")
        }
    }
}

@Composable
private fun VoiceInputButton(onResult: (String) -> Unit) {
    val context = LocalContext.current
    var isListening by remember {
        mutableStateOf(false)
    }

    val speechRecognizer = remember {
        SpeechRecognizer.createSpeechRecognizer(context)
    }

    DisposableEffect(speechRecognizer) {
        onDispose { speechRecognizer.destroy() }
    }

    val listener = remember {
        object : RecognitionListener {
            override fun onResults(bundle: Bundle) {
                val results = bundle.getStringArrayList(
                    SpeechRecognizer.RESULTS_RECOGNITION
                )
                results?.firstOrNull()?.let { onResult(it) }
                isListening = false
            }

            override fun onError(error: Int) {
                isListening = false
            }

            override fun onReadyForSpeech(params: Bundle) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        }
    }

    IconButton(
        onClick = {
            if (!isListening) {
                isListening = true
                speechRecognizer.setRecognitionListener(listener)
                val intent = Intent(
                    RecognizerIntent.ACTION_RECOGNIZE_SPEECH
                ).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                }
                speechRecognizer.startListening(intent)
            } else {
                speechRecognizer.stopListening()
                isListening = false
            }
        }
    ) {
        Icon(
            imageVector = if (isListening) Icons.Default.MicOff else Icons.Default.Mic,
            contentDescription = if (isListening) "停止录音" else "语音输入"
        )
    }
}

@Composable
private fun PermissionLevelSelector(
    selectedPermissionLevel: String?,
    onPermissionLevelSelected: (String) -> Unit
) {
    Column {
        Text("permission_level")
        listOf("local_only", "private_lan", "cloud_ok").forEach { level ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                RadioButton(
                    selected = selectedPermissionLevel == level,
                    onClick = { onPermissionLevelSelected(level) }
                )
                Text(text = level)
            }
        }
    }
}
