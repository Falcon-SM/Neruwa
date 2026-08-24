package com.falcon.neruwa.ui.screens

import android.speech.tts.TextToSpeech
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.DailyPeriod
import com.falcon.neruwa.model.Mood
import com.falcon.neruwa.model.PvtResult
import com.falcon.neruwa.ui.components.AmbientScreen
import com.falcon.neruwa.ui.components.MascotPrompt
import kotlinx.coroutines.delay
import java.util.Locale
import kotlin.random.Random

@Composable
fun DailyFlowScreen(
    period: DailyPeriod,
    repository: NeruwaRepository,
    onCancel: () -> Unit,
    onComplete: () -> Unit,
    onSleepStarted: () -> Unit
) {
    val steps = if (period == DailyPeriod.MORNING) {
        listOf("気分", "PVT", "朝テスト", "記録")
    } else {
        listOf("日記", "学習", "PVT", "音声", "睡眠")
    }
    var step by remember { mutableIntStateOf(0) }
    AmbientScreen(isNight = period == DailyPeriod.NIGHT) {
        Column(
            Modifier.fillMaxSize().padding(horizontal = 18.dp, vertical = 44.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (period == DailyPeriod.MORNING) "朝" else "夜", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text("${step + 1}/${steps.size}・${steps[step]}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                IconButton(onClick = onCancel) { Icon(Icons.Default.Close, contentDescription = "中断") }
            }
            LinearProgressIndicator(
                progress = { (step + 1f) / steps.size },
                modifier = Modifier.fillMaxWidth()
            )
            Card(
                modifier = Modifier.fillMaxWidth().weight(1f),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f)),
                shape = RoundedCornerShape(24.dp)
            ) {
                Box(Modifier.fillMaxSize().padding(18.dp)) {
                    if (period == DailyPeriod.MORNING) {
                        when (step) {
                            0 -> MorningMoodStep(repository) { step += 1 }
                            1 -> FlowPvtStep(repository, onNext = { step += 1 }, allowSkip = true)
                            2 -> MorningTestStep(repository, onNext = { step += 1 }, allowSkip = true)
                            else -> MorningSummaryStep(repository, onComplete)
                        }
                    } else {
                        when (step) {
                            0 -> JournalStep(repository) { step += 1 }
                            1 -> NightLearningStep(repository) { step += 1 }
                            2 -> FlowPvtStep(repository, onNext = { step += 1 }, allowSkip = false)
                            3 -> AudioSettingStep { step += 1 }
                            else -> NightSleepStep(repository) {
                                repository.startSleepTimer()
                                onSleepStarted()
                            }
                        }
                    }
                }
            }
            if (step > 0 && !(period == DailyPeriod.NIGHT && step == steps.lastIndex)) {
                OutlinedButton(onClick = { step -= 1 }, modifier = Modifier.fillMaxWidth()) { Text("前へ") }
            }
        }
    }
}

@Composable
private fun MorningMoodStep(repository: NeruwaRepository, onNext: () -> Unit) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        MascotPrompt("おはよう。今朝の気分を教えてね")
        Text("今日の気分", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("考えすぎず、今の感覚に近いものを選びます", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Mood.entries.forEach { mood ->
                Column(
                    modifier = Modifier.clickable {
                        repository.latestRecordWithoutMood()?.let { repository.setMood(it.id, mood) }
                        onNext()
                    }.padding(8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(mood.emoji, fontSize = 36.sp)
                    Text(mood.label, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

@Composable
private fun JournalStep(repository: NeruwaRepository, onNext: () -> Unit) {
    var journal by remember { mutableStateOf(repository.latestJournal) }
    var tasks by remember { mutableStateOf(repository.tomorrowTasks) }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        MascotPrompt("今日を閉じて、頭を休ませよう")
        Text("今日の日記", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        OutlinedTextField(journal, { journal = it }, label = { Text("今日あったこと") }, minLines = 5, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(tasks, { tasks = it }, label = { Text("明日やりたいこと") }, minLines = 3, modifier = Modifier.fillMaxWidth())
        Spacer(Modifier.weight(1f))
        Button(
            onClick = { repository.saveJournal(journal, tasks); onNext() },
            modifier = Modifier.fillMaxWidth()
        ) { Text("次へ") }
    }
}

@Composable
private fun NightLearningStep(repository: NeruwaRepository, onNext: () -> Unit) {
    var index by remember { mutableIntStateOf(0) }
    var answer by remember { mutableStateOf(false) }
    val cards = repository.learningCards.take(5)
    val card = cards.getOrNull(index)
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("睡眠学習", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth())
        Text("眠る前に覚えたい内容を確認します", modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (card != null) {
            Card(
                modifier = Modifier.fillMaxWidth().weight(1f).clickable { answer = !answer },
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Column(Modifier.fillMaxSize().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                    Text(card.prompt, style = MaterialTheme.typography.headlineMedium)
                    if (answer) Text(card.answer, style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.secondary)
                    else Text("タップして答えを見る", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Button(
                onClick = {
                    if (index >= cards.lastIndex) onNext() else { index += 1; answer = false }
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (index >= cards.lastIndex) "次へ" else "次のカード") }
        } else {
            Text("学習カードがありません")
            Button(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("次へ") }
        }
    }
}

@Composable
private fun MorningTestStep(repository: NeruwaRepository, onNext: () -> Unit, allowSkip: Boolean) {
    val card = repository.learningCards.firstOrNull()
    var selected by remember { mutableStateOf<String?>(null) }
    val choices = remember(card) {
        if (card == null) emptyList() else (listOf(card.answer) + repository.learningCards.map { it.answer }.filter { it != card.answer }.take(3)).shuffled()
    }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        MascotPrompt("眠る前に見たカードを思い出してみよう")
        Text("朝テスト", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(card?.prompt ?: "カードがありません", style = MaterialTheme.typography.headlineMedium)
        choices.forEach { choice ->
            OutlinedButton(onClick = { selected = choice }, modifier = Modifier.fillMaxWidth()) {
                Text(choice)
            }
        }
        if (selected != null) {
            Text(if (selected == card?.answer) "正解！" else "答えは ${card?.answer}", color = MaterialTheme.colorScheme.tertiary)
            Button(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("次へ") }
        }
        if (allowSkip && selected == null) OutlinedButton(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("テストを飛ばす") }
    }
}

@Composable
private fun FlowPvtStep(repository: NeruwaRepository, onNext: () -> Unit, allowSkip: Boolean) {
    var started by remember { mutableStateOf(false) }
    var ready by remember { mutableStateOf(false) }
    var remaining by remember { mutableIntStateOf(90) }
    var reactions by remember { mutableStateOf(listOf<Int>()) }
    var readyAt by remember { mutableStateOf(0L) }

    LaunchedEffect(started) {
        if (!started) return@LaunchedEffect
        val start = System.currentTimeMillis()
        while (System.currentTimeMillis() - start < 90_000L) {
            ready = false
            delay(Random.nextLong(1_200, 3_500))
            readyAt = System.nanoTime()
            ready = true
            delay(1_500)
            remaining = (90 - (System.currentTimeMillis() - start) / 1_000).toInt().coerceAtLeast(0)
        }
        ready = false
        started = false
        repository.addPvtResult(
            PvtResult(
                averageReactionMillis = reactions.average().takeIf { !it.isNaN() }?.toInt() ?: 0,
                lapses = 0,
                falseStarts = 0
            )
        )
        onNext()
    }

    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("PVT", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, modifier = Modifier.fillMaxWidth())
        Text("光ったら素早くタップします（90秒）", modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(Color(0xFF101427), RoundedCornerShape(24.dp))
                .clickable {
                    if (ready) {
                        reactions = reactions + ((System.nanoTime() - readyAt) / 1_000_000L).toInt()
                        ready = false
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            if (ready) Box(Modifier.size(110.dp).background(MaterialTheme.colorScheme.secondary, CircleShape))
            else Text(if (started) "待って…" else "開始を押してください")
            if (started) Text("残り${remaining}秒", Modifier.align(Alignment.TopEnd).padding(14.dp))
        }
        Button(onClick = { started = true }, enabled = !started, modifier = Modifier.fillMaxWidth()) { Text("90秒テストを開始") }
        if (allowSkip) OutlinedButton(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("PVTを飛ばす") }
    }
}

@Composable
private fun AudioSettingStep(onNext: () -> Unit) {
    val context = LocalContext.current
    val tts = remember { TextToSpeech(context) {} }
    var interval by remember { mutableIntStateOf(300) }
    var volume by remember { mutableIntStateOf(80) }
    DisposableEffect(tts) { onDispose { tts.shutdown() } }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("睡眠音声", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("睡眠中に学習カードを読み上げる間隔を設定します", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("再生間隔", fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(5, 60, 300).forEach { seconds ->
                FilterChip(selected = interval == seconds, onClick = { interval = seconds }, label = { Text(if (seconds == 5) "5秒（デモ）" else "${seconds / 60}分") })
            }
        }
        Text("音量 $volume%", fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(60, 80, 100).forEach { value ->
                FilterChip(selected = volume == value, onClick = { volume = value }, label = { Text("$value%") })
            }
        }
        OutlinedButton(
            onClick = {
                tts.language = Locale.JAPAN
                tts.speak("ねるるん。睡眠学習の音声テストです", TextToSpeech.QUEUE_FLUSH, null, "preview")
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.VolumeUp, contentDescription = null)
            Text("音を試す", modifier = Modifier.padding(start = 8.dp))
        }
        Spacer(Modifier.weight(1f))
        Button(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("次へ") }
    }
}

@Composable
private fun NightSleepStep(repository: NeruwaRepository, onStart: () -> Unit) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        MascotPrompt("準備ができたね。今日を終えて眠ろう")
        Spacer(Modifier.height(24.dp))
        Text("目標 ${repository.targetMinutes / 60}時間${repository.targetMinutes % 60}分", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(24.dp))
        Button(onClick = onStart, modifier = Modifier.fillMaxWidth()) { Text("睡眠を開始") }
    }
}

@Composable
private fun MorningSummaryStep(repository: NeruwaRepository, onComplete: () -> Unit) {
    val latest = repository.sleepRecords.maxByOrNull { it.wakeMillis }
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        MascotPrompt("朝の記録が完了したよ")
        Text("今日の記録", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(
            latest?.let { "${it.durationMinutes / 60}時間${it.durationMinutes % 60}分　${it.mood?.emoji ?: ""}" } ?: "睡眠記録なし",
            style = MaterialTheme.typography.displaySmall
        )
        Text("記録を続けると、睡眠時間と気分の関係が見えてきます", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Button(onClick = onComplete, modifier = Modifier.fillMaxWidth()) { Text("記録を見る") }
    }
}
