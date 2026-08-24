package com.falcon.neruwa.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.falcon.neruwa.data.NeruwaRepository
import com.falcon.neruwa.model.PvtResult
import com.falcon.neruwa.ui.components.MascotPrompt
import kotlinx.coroutines.delay
import kotlin.math.roundToInt
import kotlin.random.Random

private enum class PvtRange(val label: String, val millis: Long) {
    DAY("1日", 24 * 60 * 60 * 1_000L),
    WEEK("1週間", 7 * 24 * 60 * 60 * 1_000L),
    MONTH("1ヶ月", 31 * 24 * 60 * 60 * 1_000L)
}

@Composable
fun PvtScreen(repository: NeruwaRepository, modifier: Modifier = Modifier) {
    var running by remember { mutableStateOf(false) }
    var ready by remember { mutableStateOf(false) }
    var startedAt by remember { mutableLongStateOf(0L) }
    var readyAt by remember { mutableLongStateOf(0L) }
    var remainingSeconds by remember { mutableIntStateOf(90) }
    var responseNonce by remember { mutableIntStateOf(0) }
    var falseStarts by remember { mutableIntStateOf(0) }
    var lapses by remember { mutableIntStateOf(0) }
    val reactions = remember { mutableStateListOf<Int>() }
    var range by remember { mutableStateOf(PvtRange.WEEK) }

    LaunchedEffect(running) {
        if (!running) return@LaunchedEffect
        startedAt = System.currentTimeMillis()
        remainingSeconds = 90
        falseStarts = 0
        lapses = 0
        reactions.clear()
        while (running && System.currentTimeMillis() - startedAt < 90_000L) {
            ready = false
            delay(Random.nextLong(1_200L, 4_200L))
            if (!running || System.currentTimeMillis() - startedAt >= 90_000L) break
            val baseline = responseNonce
            readyAt = System.nanoTime()
            ready = true
            while (ready && responseNonce == baseline && System.nanoTime() - readyAt < 2_000_000_000L) {
                remainingSeconds = (90 - (System.currentTimeMillis() - startedAt) / 1_000L).toInt().coerceAtLeast(0)
                delay(10)
            }
            if (responseNonce == baseline) {
                lapses += 1
                ready = false
            }
        }
        ready = false
        running = false
        remainingSeconds = 0
        val average = reactions.average().takeIf { !it.isNaN() }?.roundToInt() ?: 0
        repository.addPvtResult(PvtResult(averageReactionMillis = average, lapses = lapses, falseStarts = falseStarts))
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item { MascotPrompt("光ったら、できるだけ早くタップしてね") }
        item {
            Text("PVT", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text("90秒間、眠気による反応速度の変化を測ります", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        item {
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp)
                    .clickable {
                        if (!running) return@clickable
                        if (ready) {
                            reactions.add(((System.nanoTime() - readyAt) / 1_000_000L).toInt())
                            responseNonce += 1
                            ready = false
                        } else {
                            falseStarts += 1
                        }
                    },
                shape = RoundedCornerShape(28.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF111729))
            ) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (ready) {
                        Box(Modifier.size(116.dp).background(MaterialTheme.colorScheme.secondary, CircleShape))
                    } else {
                        Text(
                            when {
                                !running && reactions.isEmpty() -> "開始を押してください"
                                !running -> "完了"
                                else -> "待って…"
                            },
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    if (running) Text("残り ${remainingSeconds}秒", Modifier.align(Alignment.TopEnd).padding(16.dp))
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("平均 ${reactions.average().takeIf { !it.isNaN() }?.roundToInt() ?: 0} ms")
                Text("遅延 $lapses")
                Text("フライング $falseStarts")
            }
            Button(
                onClick = { running = !running },
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (running) "中断" else "90秒テストを開始") }
        }
        item {
            Text("結果の比較", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PvtRange.entries.forEach { item ->
                    FilterChip(selected = range == item, onClick = { range = item }, label = { Text(item.label) })
                }
            }
            PvtChart(
                repository.pvtResults.filter { System.currentTimeMillis() - it.measuredAtMillis <= range.millis }
            )
        }
    }
}

@Composable
private fun PvtChart(results: List<PvtResult>) {
    val lineColor = MaterialTheme.colorScheme.primary
    val points = results.sortedBy { it.measuredAtMillis }.takeLast(30)
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(180.dp)
            .padding(vertical = 16.dp)
    ) {
        repeat(4) { row ->
            val y = size.height * row / 3f
            drawLine(Color.White.copy(alpha = 0.10f), Offset(0f, y), Offset(size.width, y), 2f)
        }
        if (points.isEmpty()) return@Canvas
        val minValue = points.minOf { it.averageReactionMillis }.coerceAtMost(200)
        val maxValue = points.maxOf { it.averageReactionMillis }.coerceAtLeast(minValue + 100)
        val coordinates = points.mapIndexed { index, result ->
            val x = if (points.size == 1) size.width / 2f else size.width * index / (points.size - 1f)
            val ratio = (result.averageReactionMillis - minValue).toFloat() / (maxValue - minValue)
            Offset(x, size.height * (1f - ratio.coerceIn(0f, 1f)))
        }
        coordinates.zipWithNext().forEach { (start, end) ->
            drawLine(lineColor, start, end, strokeWidth = 6f, cap = StrokeCap.Round)
        }
        coordinates.forEach { drawCircle(lineColor, 7f, it) }
    }
}
