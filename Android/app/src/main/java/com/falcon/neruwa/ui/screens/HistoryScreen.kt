package com.falcon.neruwa.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.Mood
import com.falcon.neruwa.model.SleepRecord
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter

@Composable
fun HistoryScreen(repository: NeruwaRepository, modifier: Modifier = Modifier) {
    var month by remember { mutableStateOf(YearMonth.now()) }
    var selectedDate by remember { mutableStateOf<LocalDate?>(null) }
    val recordsByDate = repository.sleepRecords.groupBy { it.wakeDate }
    val selectedRecords = selectedDate?.let { recordsByDate[it].orEmpty() }.orEmpty()

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { month = month.minusMonths(1) }) {
                    Icon(Icons.Default.ChevronLeft, contentDescription = "前月")
                }
                Text(
                    "${month.year}年 ${month.monthValue}月",
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                IconButton(onClick = { month = month.plusMonths(1) }) {
                    Icon(Icons.Default.ChevronRight, contentDescription = "次月")
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth()) {
                listOf("月", "火", "水", "木", "金", "土", "日").forEach {
                    Text(it, modifier = Modifier.weight(1f), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            val dates = calendarDates(month)
            LazyVerticalGrid(
                columns = GridCells.Fixed(7),
                modifier = Modifier.fillMaxWidth().aspectRatio(7f / 6.2f),
                userScrollEnabled = false
            ) {
                items(dates) { date ->
                    if (date == null) Box(Modifier.aspectRatio(1f)) else {
                        val record = recordsByDate[date]?.maxByOrNull { it.wakeMillis }
                        CalendarDay(
                            date = date,
                            record = record,
                            selected = selectedDate == date,
                            onClick = { selectedDate = date }
                        )
                    }
                }
            }
        }
        item {
            val monthRecords = repository.sleepRecords.filter { YearMonth.from(it.wakeDate) == month }
            val average = monthRecords.map { it.durationMinutes }.takeIf { it.isNotEmpty() }?.average()?.toInt() ?: 0
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f))) {
                Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceAround) {
                    SummaryValue("記録", "${monthRecords.size}日")
                    SummaryValue("平均", "${average / 60}時間${average % 60}分")
                    SummaryValue("目標", "${repository.targetMinutes / 60}時間")
                }
            }
        }
        if (selectedDate != null) {
            item {
                Text(
                    selectedDate!!.format(DateTimeFormatter.ofPattern("M月d日の詳細")),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                if (selectedRecords.isEmpty()) {
                    Text("この日の睡眠記録はありません", color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    selectedRecords.forEach { SleepDetail(it) }
                }
            }
        }
    }
}

@Composable
private fun CalendarDay(date: LocalDate, record: SleepRecord?, selected: Boolean, onClick: () -> Unit) {
    val moodColor = when (record?.mood) {
        Mood.BAD -> Color(0xFFE56B6F)
        Mood.FLAT -> Color(0xFFF2CC8F)
        Mood.GOOD -> Color(0xFF81B29A)
        Mood.GREAT -> Color(0xFF64B5F6)
        null -> MaterialTheme.colorScheme.surfaceVariant
    }
    Column(
        modifier = Modifier
            .aspectRatio(0.86f)
            .padding(2.dp)
            .background(
                if (selected) MaterialTheme.colorScheme.primaryContainer else moodColor.copy(alpha = if (record == null) 0.28f else 0.42f),
                RoundedCornerShape(10.dp)
            )
            .clickable(onClick = onClick)
            .padding(4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Text("${date.dayOfMonth}", style = MaterialTheme.typography.labelMedium)
        if (record != null) {
            Text(
                "${record.durationMinutes / 60}:${(record.durationMinutes % 60).toString().padStart(2, '0')}",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun SummaryValue(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SleepDetail(record: SleepRecord) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${record.durationMinutes / 60}時間${record.durationMinutes % 60}分", fontWeight = FontWeight.Bold)
            Text("記録方法：${record.source}", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("気分：${record.mood?.emoji ?: "未記録"}")
        }
    }
}

private fun calendarDates(month: YearMonth): List<LocalDate?> {
    val first = month.atDay(1)
    val leading = (first.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
    val result = MutableList<LocalDate?>(leading) { null }
    repeat(month.lengthOfMonth()) { result.add(month.atDay(it + 1)) }
    while (result.size % 7 != 0) result.add(null)
    return result
}
