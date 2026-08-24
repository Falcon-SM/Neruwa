package com.falcon.neruwa.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.Mood
import com.falcon.neruwa.model.NerurunEvaluator
import com.falcon.neruwa.ui.components.NerurunStatusCard
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

@Composable
fun SleepScreen(
    repository: NeruwaRepository,
    modifier: Modifier = Modifier,
    onWake: () -> Unit
) {
    if (repository.sleepTimerStartMillis > 0L) {
        ActiveSleepTimer(repository, modifier, onWake)
        return
    }

    var bedtimeHour by remember { mutableIntStateOf(23) }
    var bedtimeMinute by remember { mutableIntStateOf(0) }
    var wakeHour by remember { mutableIntStateOf(7) }
    var wakeMinute by remember { mutableIntStateOf(0) }
    val status = NerurunEvaluator.evaluate(repository.sleepRecords, repository.targetMinutes)
    val duration = ((wakeHour * 60 + wakeMinute) - (bedtimeHour * 60 + bedtimeMinute) + 24 * 60) % (24 * 60)

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { NerurunStatusCard(status) }
        repository.latestRecordWithoutMood()?.let { record ->
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("今朝の気分", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Mood.entries.forEach { mood ->
                            FilledTonalButton(onClick = { repository.setMood(record.id, mood) }, shape = CircleShape) {
                                Text(mood.emoji)
                            }
                        }
                    }
                }
            }
        }
        item {
            Text("睡眠時間", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            SleepDurationClock(durationMinutes = duration)
            Text(
                "${duration / 60}時間${duration % 60}分",
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.fillMaxWidth(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
        item {
            TimeSelector("就寝時刻", bedtimeHour, bedtimeMinute) { hour, minute ->
                bedtimeHour = hour
                bedtimeMinute = minute
            }
            Spacer(Modifier.height(10.dp))
            TimeSelector("起床時刻", wakeHour, wakeMinute) { hour, minute ->
                wakeHour = hour
                wakeMinute = minute
            }
        }
        item {
            Button(
                onClick = {
                    val zone = ZoneId.systemDefault()
                    val today = LocalDate.now()
                    var bedtime = today.minusDays(1).atTime(bedtimeHour, bedtimeMinute).atZone(zone)
                    var wake = today.atTime(wakeHour, wakeMinute).atZone(zone)
                    if (!wake.isAfter(bedtime)) wake = wake.plusDays(1)
                    repository.addManualSleep(bedtime.toInstant().toEpochMilli(), wake.toInstant().toEpochMilli())
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                androidx.compose.material3.Icon(Icons.Default.Check, contentDescription = null)
                Text("この時間で記録", modifier = Modifier.padding(start = 8.dp))
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(onClick = repository::startSleepTimer, modifier = Modifier.fillMaxWidth()) {
                androidx.compose.material3.Icon(Icons.Default.Bedtime, contentDescription = null)
                Text("睡眠を開始", modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}

@Composable
private fun ActiveSleepTimer(repository: NeruwaRepository, modifier: Modifier, onWake: () -> Unit) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1_000)
        }
    }
    val elapsed = (now - repository.sleepTimerStartMillis).coerceAtLeast(0L) / 1_000
    Column(
        modifier = modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("おやすみなさい", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))
        Text("ねるるんが朝まで見守っています", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.height(32.dp))
        SleepDurationClock((elapsed / 60).toInt(), Modifier.size(260.dp))
        Text(
            "%02d:%02d:%02d".format(elapsed / 3600, elapsed % 3600 / 60, elapsed % 60),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Light
        )
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = {
                repository.finishSleepTimer()
                onWake()
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("起床して記録") }
        OutlinedButton(onClick = repository::cancelSleepTimer, modifier = Modifier.fillMaxWidth()) {
            Text("計測を取り消す")
        }
    }
}

@Composable
private fun TimeSelector(label: String, hour: Int, minute: Int, onChange: (Int, Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
        OutlinedButton(onClick = { onChange((hour + 23) % 24, minute) }) { Text("−") }
        Text("%02d:%02d".format(hour, minute), modifier = Modifier.padding(horizontal = 12.dp))
        OutlinedButton(onClick = { onChange((hour + 1) % 24, minute) }) { Text("＋") }
        OutlinedButton(onClick = { onChange(hour, (minute + 15) % 60) }) { Text("15分") }
    }
}

@Composable
private fun SleepDurationClock(durationMinutes: Int, modifier: Modifier = Modifier.size(220.dp)) {
    val primary = MaterialTheme.colorScheme.secondary
    val onSurface = MaterialTheme.colorScheme.onSurface
    Canvas(modifier.padding(12.dp)) {
        val radius = min(size.width, size.height) / 2f
        val center = Offset(size.width / 2f, size.height / 2f)
        drawCircle(Color(0xFF101427), radius, center)
        drawCircle(Color.White.copy(alpha = 0.18f), radius, center, style = Stroke(6f))
        repeat(12) { index ->
            val angle = Math.toRadians(index * 30.0 - 90.0)
            val start = Offset(
                center.x + cos(angle).toFloat() * radius * 0.82f,
                center.y + sin(angle).toFloat() * radius * 0.82f
            )
            val end = Offset(
                center.x + cos(angle).toFloat() * radius * 0.92f,
                center.y + sin(angle).toFloat() * radius * 0.92f
            )
            drawLine(onSurface.copy(alpha = 0.8f), start, end, strokeWidth = 4f, cap = StrokeCap.Round)
        }
        val handAngle = Math.toRadians((durationMinutes % 720) / 2.0 - 90.0)
        drawLine(
            primary,
            center,
            Offset(
                center.x + cos(handAngle).toFloat() * radius * 0.58f,
                center.y + sin(handAngle).toFloat() * radius * 0.58f
            ),
            strokeWidth = 8f,
            cap = StrokeCap.Round
        )
        drawCircle(primary, 11f, center)
    }
}
