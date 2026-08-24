package com.falcon.neruwa.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

enum class Mood(val emoji: String, val label: String, val color: Long) {
    BAD("😣", "つらい", 0xFFE56B6F),
    FLAT("😐", "ふつう", 0xFFF2CC8F),
    GOOD("🙂", "いい", 0xFF81B29A),
    GREAT("😄", "最高", 0xFF64B5F6)
}

data class SleepRecord(
    val id: String = UUID.randomUUID().toString(),
    val bedtimeMillis: Long,
    val wakeMillis: Long,
    val targetMinutes: Int = 480,
    val mood: Mood? = null,
    val source: String = "手入力"
) {
    val durationMinutes: Int
        get() = ((wakeMillis - bedtimeMillis).coerceAtLeast(0L) / 60_000L).toInt()

    val wakeDate: LocalDate
        get() = Instant.ofEpochMilli(wakeMillis).atZone(ZoneId.systemDefault()).toLocalDate()
}

data class LearningCard(
    val id: String = UUID.randomUUID().toString(),
    val prompt: String,
    val answer: String,
    val speech: String = answer,
    val language: String = "ja-JP",
    val folder: String = "点字",
    val brailleDots: List<Int> = emptyList()
)

data class PvtResult(
    val id: String = UUID.randomUUID().toString(),
    val measuredAtMillis: Long = System.currentTimeMillis(),
    val averageReactionMillis: Int,
    val lapses: Int,
    val falseStarts: Int
)

data class SharePost(
    val id: String = UUID.randomUUID().toString(),
    val author: String,
    val createdAtMillis: Long = System.currentTimeMillis(),
    val sleepMinutes: Int,
    val mood: Mood?,
    val message: String,
    val visibility: String = "みんな"
)

enum class NerurunCondition(val title: String, val message: String) {
    NORMAL("いつものねるるん", "今日の眠りも一緒に記録しよう"),
    DISCOURAGED("ちょっとしょんぼり", "クローバーも少し元気がないみたい。今夜は早めに休もう"),
    EXHAUSTED("疲れが限界かも", "目の下にクマができているよ。今日は睡眠を最優先にしよう"),
    THRIVING("とてもいいペース", "記録も睡眠も安定しているよ。小さな仲間が増えました")
}

data class NerurunStatus(
    val condition: NerurunCondition,
    val companionCount: Int = 0
)

enum class DailyPeriod { MORNING, NIGHT }

data class DailySchedule(
    val morningStartMinutes: Int = 4 * 60,
    val nightStartMinutes: Int = 19 * 60
) {
    fun periodAt(hour: Int, minute: Int): DailyPeriod {
        val now = hour * 60 + minute
        return if (now >= nightStartMinutes || now < morningStartMinutes) {
            DailyPeriod.NIGHT
        } else {
            DailyPeriod.MORNING
        }
    }
}
