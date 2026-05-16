package com.gemma4all.mobilehost.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.gemma4all.mobilehost.models.Device

@Composable
fun DeviceSettingsScreen(
    device: Device?,
    onDeviceNameChanged: (String) -> Unit = {},
    onPermissionScopeChanged: (String) -> Unit = {}
) {
    var deviceName by remember(device?.deviceName) { mutableStateOf(device?.deviceName.orEmpty()) }
    var permissionScope by remember(device?.permissionScope) {
        mutableStateOf(device?.permissionScope.orEmpty())
    }

    Column(modifier = Modifier.padding(16.dp)) {
        OutlinedTextField(
            value = deviceName,
            onValueChange = {
                deviceName = it
                onDeviceNameChanged(it)
            },
            label = { Text("device_name") }
        )
        Text("runtime_type: ${device?.runtimeType.orEmpty()}")
        Text("registered_at: ${device?.registeredAt.orEmpty()}")
        Text("permission_scope")
        listOf("local_only", "private_lan", "cloud_ok").forEach { scope ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                RadioButton(
                    selected = permissionScope == scope,
                    onClick = {
                        permissionScope = scope
                        onPermissionScopeChanged(scope)
                    }
                )
                Text(scope)
            }
        }
        Text("local_only: 仅本设备处理")
        Text("private_lan: 同账号受信局域网设备可处理")
        Text("cloud_ok: 可路由到云端 runtime")
    }
}
