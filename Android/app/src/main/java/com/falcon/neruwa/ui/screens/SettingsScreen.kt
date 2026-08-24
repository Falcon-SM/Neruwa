package com.falcon.neruwa.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.DailyPeriod
import com.falcon.neruwa.model.DailySchedule
import kotlin.math.roundToInt

@Composable
fun SettingsScreen(
    repository: NeruwaRepository,
    modifier: Modifier = Modifier,
    onStartFlow: (DailyPeriod) -> Unit
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            SettingsCard("目標睡眠時間") {
                Text("${repository.targetMinutes / 60}時間${repository.targetMinutes % 60}分", style = MaterialTheme.typography.headlineSmall)
                Slider(
                    value = repository.targetMinutes.toFloat(),
                    onValueChange = { repository.updateTarget((it / 15).roundToInt() * 15) },
                    valueRange = 360f..600f,
                    steps = 15
                )
            }
        }
        item {
            SettingsCard("朝と夜の時間") {
                TimeSettingRow("朝の開始", repository.schedule.morningStartMinutes) { value ->
                    repository.updateSchedule(repository.schedule.copy(morningStartMinutes = value))
                }
                TimeSettingRow("夜の開始", repository.schedule.nightStartMinutes) { value ->
                    repository.updateSchedule(repository.schedule.copy(nightStartMinutes = value))
                }
                Text("夜の開始から朝の開始までは夜の流れ、それ以外は朝の流れです", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            SettingsCard("就寝前のリマインド") {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    (0..5).forEach { count ->
                        FilterChip(
                            selected = repository.reminderCount == count,
                            onClick = { repository.updateReminderCount(count) },
                            label = { Text("$count") }
                        )
                    }
                }
                Text("通知回数は端末に合わせて調整できます", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            SettingsCard("共有の公開範囲") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("みんな", "この端末のみ").forEach {
                        FilterChip(
                            selected = repository.defaultVisibility == it,
                            onClick = { repository.updateVisibility(it) },
                            label = { Text(it) }
                        )
                    }
                }
            }
        }
        item {
            SettingsCard("デモ") {
                Text("時間に関係なく、朝・夜の必須フローを確認できます", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = { onStartFlow(DailyPeriod.MORNING) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Text("朝の流れを始める", modifier = Modifier.padding(start = 8.dp))
                }
                OutlinedButton(onClick = { onStartFlow(DailyPeriod.NIGHT) }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.DarkMode, contentDescription = null)
                    Text("夜の流れを始める", modifier = Modifier.padding(start = 8.dp))
                }
            }
        }
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f))) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            content()
        }
    }
}

@Composable
private fun TimeSettingRow(label: String, minutes: Int, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, modifier = Modifier.weight(1f))
        OutlinedButton(onClick = { onChange((minutes - 30 + 1440) % 1440) }) { Text("−") }
        Text("%02d:%02d".format(minutes / 60, minutes % 60), modifier = Modifier.padding(vertical = 12.dp))
        OutlinedButton(onClick = { onChange((minutes + 30) % 1440) }) { Text("＋") }
    }
}
