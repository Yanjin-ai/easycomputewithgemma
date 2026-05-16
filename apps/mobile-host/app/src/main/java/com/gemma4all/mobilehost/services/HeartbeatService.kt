package com.gemma4all.mobilehost.services

import com.gemma4all.mobilehost.client.ControlPlaneApi
import com.gemma4all.mobilehost.models.HeartbeatRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

interface HeartbeatService {
    fun start(deviceId: String)
    fun stop()
}

class PollingHeartbeatService @Inject constructor(
    private val api: ControlPlaneApi
) : HeartbeatService {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var heartbeatJob: Job? = null

    override fun start(deviceId: String) {
        stop()
        heartbeatJob = scope.launch {
            while (isActive) {
                api.postHeartbeat(
                    HeartbeatRequest(
                        deviceId = deviceId,
                        isOnline = true,
                        networkType = "wifi",
                        activeRunCount = 0,
                        supportedTools = emptyList(),
                        supportedCapabilities = emptyList()
                    )
                )
                delay(15_000)
            }
        }
    }

    override fun stop() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }
}
