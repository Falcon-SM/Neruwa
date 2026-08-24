package com.falcon.neruwa.ui.screens

import android.speech.tts.TextToSpeech
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.LearningCard
import com.falcon.neruwa.ui.components.MascotPrompt
import java.util.Locale

@Composable
fun LearningScreen(repository: NeruwaRepository, modifier: Modifier = Modifier) {
    var selectedFolder by remember { mutableStateOf("すべて") }
    var cardIndex by remember { mutableIntStateOf(0) }
    var showAnswer by remember { mutableStateOf(false) }
    var showAdd by remember { mutableStateOf(false) }
    var showImport by remember { mutableStateOf(false) }
    val folders = listOf("すべて") + repository.learningCards.map { it.folder }.distinct()
    val cards = repository.learningCards.filter { selectedFolder == "すべて" || it.folder == selectedFolder }
    val card = cards.getOrNull(cardIndex.coerceAtMost((cards.size - 1).coerceAtLeast(0)))
    val context = LocalContext.current
    val tts = remember { TextToSpeech(context) {} }

    DisposableEffect(tts) {
        onDispose { tts.shutdown() }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { MascotPrompt("今日も少しずつ覚えていこう") }
        item {
            Text("フォルダ", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                folders.forEach { folder ->
                    FilterChip(
                        selected = selectedFolder == folder,
                        onClick = {
                            selectedFolder = folder
                            cardIndex = 0
                            showAnswer = false
                        },
                        label = { Text(folder) }
                    )
                }
            }
        }
        item {
            Text("学習カード", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            if (card == null) {
                Text("このフォルダにカードはありません", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                LearningCardView(
                    card = card,
                    index = cardIndex,
                    total = cards.size,
                    showAnswer = showAnswer,
                    onToggle = {
                        showAnswer = !showAnswer
                        if (showAnswer) speakCard(tts, card)
                    },
                    onSpeak = { speakCard(tts, card) }
                )
            }
        }
        if (cards.isNotEmpty()) {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(
                        onClick = { cardIndex = (cardIndex - 1).coerceAtLeast(0); showAnswer = false },
                        enabled = cardIndex > 0,
                        modifier = Modifier.weight(1f)
                    ) { Text("前へ") }
                    Button(
                        onClick = { cardIndex = (cardIndex + 1).coerceAtMost(cards.lastIndex); showAnswer = false },
                        enabled = cardIndex < cards.lastIndex,
                        modifier = Modifier.weight(1f)
                    ) { Text("次へ") }
                }
            }
        }
        item {
            OutlinedButton(onClick = { showAdd = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.Add, contentDescription = null)
                Text("自分のカードを追加", modifier = Modifier.padding(start = 8.dp))
            }
            OutlinedButton(onClick = { showImport = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Default.FileUpload, contentDescription = null)
                Text("CSVをインポート", modifier = Modifier.padding(start = 8.dp))
            }
        }
    }

    if (showAdd) AddCardDialog(repository) { showAdd = false }
    if (showImport) ImportCsvDialog(repository) { showImport = false }
}

@Composable
private fun LearningCardView(
    card: LearningCard,
    index: Int,
    total: Int,
    showAnswer: Boolean,
    onToggle: () -> Unit,
    onSpeak: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            Modifier.fillMaxWidth().padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(Modifier.fillMaxWidth()) {
                Text("${index + 1} / $total", fontWeight = FontWeight.Bold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text(card.language, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(card.prompt, style = MaterialTheme.typography.headlineSmall)
            if (card.brailleDots.isNotEmpty()) BrailleDots(card.brailleDots)
            if (showAnswer) {
                Text(card.answer, style = MaterialTheme.typography.displaySmall, color = MaterialTheme.colorScheme.secondary)
            } else {
                Text("カードをタップして答えを見る", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(onClick = onSpeak) { Icon(Icons.Default.VolumeUp, contentDescription = "読み上げ") }
        }
    }
}

@Composable
private fun BrailleDots(active: List<Int>) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        repeat(2) { column ->
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                repeat(3) { row ->
                    val number = if (column == 0) row + 1 else row + 4
                    Box(
                        Modifier
                            .size(28.dp)
                            .background(
                                if (number in active) MaterialTheme.colorScheme.primary else Color.White.copy(alpha = 0.12f),
                                CircleShape
                            )
                    )
                }
            }
        }
    }
}

private fun speakCard(tts: TextToSpeech, card: LearningCard) {
    tts.language = if (card.language.startsWith("en")) Locale.US else Locale.JAPAN
    tts.setSpeechRate(0.86f)
    tts.setPitch(1.0f)
    tts.speak(card.speech, TextToSpeech.QUEUE_FLUSH, null, card.id)
}

@Composable
private fun AddCardDialog(repository: NeruwaRepository, onDismiss: () -> Unit) {
    var prompt by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf("") }
    var folder by remember { mutableStateOf("自分のカード") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("カードを追加") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(prompt, { prompt = it }, label = { Text("問題") })
                OutlinedTextField(answer, { answer = it }, label = { Text("答え・読み上げ") })
                OutlinedTextField(folder, { folder = it }, label = { Text("フォルダ") })
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    repository.addCard(LearningCard(prompt = prompt, answer = answer, folder = folder))
                    onDismiss()
                },
                enabled = prompt.isNotBlank() && answer.isNotBlank()
            ) { Text("追加") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } }
    )
}

@Composable
private fun ImportCsvDialog(repository: NeruwaRepository, onDismiss: () -> Unit) {
    var csv by remember { mutableStateOf("") }
    var result by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("CSVインポート") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("prompt,answer,speech,language,folder の順で貼り付けます")
                OutlinedTextField(csv, { csv = it }, label = { Text("CSV") }, minLines = 6)
                if (result.isNotBlank()) Text(result, color = MaterialTheme.colorScheme.tertiary)
            }
        },
        confirmButton = {
            TextButton(onClick = { result = "${repository.importCsv(csv)}枚を追加しました" }) { Text("読み込む") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("閉じる") } }
    )
}
