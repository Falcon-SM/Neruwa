package com.falcon.neruwa.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.Mood
import com.falcon.neruwa.model.SharePost
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun ShareScreen(repository: NeruwaRepository, modifier: Modifier = Modifier) {
    var mode by remember { mutableStateOf("みんなの睡眠") }
    Column(modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            listOf("みんなの睡眠", "投稿する").forEachIndexed { index, label ->
                SegmentedButton(
                    selected = mode == label,
                    onClick = { mode = label },
                    shape = SegmentedButtonDefaults.itemShape(index, 2)
                ) { Text(label) }
            }
        }
        if (mode == "みんなの睡眠") {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item {
                    Text("みんなの投稿", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("睡眠の達成をゆるく共有して、続けるきっかけにします", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                items(repository.sharePosts, key = { it.id }) { post -> SharePostCard(post) }
            }
        } else {
            CreatePost(repository) { mode = "みんなの睡眠" }
        }
    }
}

@Composable
private fun SharePostCard(post: SharePost) {
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f))
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Person, contentDescription = null, modifier = Modifier.padding(end = 8.dp))
                Column {
                    Text(post.author, fontWeight = FontWeight.Bold)
                    Text(
                        Instant.ofEpochMilli(post.createdAtMillis).atZone(ZoneId.systemDefault())
                            .format(DateTimeFormatter.ofPattern("M/d HH:mm")),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text(post.mood?.emoji ?: "🌙")
            }
            Text("${post.sleepMinutes / 60}時間${post.sleepMinutes % 60}分", style = MaterialTheme.typography.headlineSmall)
            Text(post.message)
        }
    }
}

@Composable
private fun CreatePost(repository: NeruwaRepository, onPosted: () -> Unit) {
    var message by remember { mutableStateOf("") }
    var mood by remember { mutableStateOf<Mood?>(null) }
    var visibility by remember { mutableStateOf(repository.defaultVisibility) }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Text("睡眠を共有", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("日記本文や個人的なデータは投稿されません", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Text("気分", fontWeight = FontWeight.SemiBold)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Mood.entries.forEach { item ->
                    FilterChip(
                        selected = mood == item,
                        onClick = { mood = item },
                        label = { Text(item.emoji) },
                        shape = CircleShape
                    )
                }
            }
        }
        item {
            OutlinedTextField(
                value = message,
                onValueChange = { message = it.take(120) },
                label = { Text("ひとこと") },
                supportingText = { Text("${message.length}/120") },
                minLines = 3,
                modifier = Modifier.fillMaxWidth()
            )
        }
        item {
            Text("公開範囲", fontWeight = FontWeight.SemiBold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("みんな", "この端末のみ").forEach {
                    FilterChip(selected = visibility == it, onClick = { visibility = it }, label = { Text(it) })
                }
            }
        }
        item {
            Button(
                onClick = {
                    repository.addSharePost(message, mood, visibility)
                    onPosted()
                },
                enabled = message.isNotBlank(),
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(Icons.Default.Send, contentDescription = null)
                Text("投稿する", modifier = Modifier.padding(start = 8.dp))
            }
        }
    }
}
