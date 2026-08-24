package com.falcon.neruwa.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.falcon.neruwa.model.DailyPeriod
import com.falcon.neruwa.model.DailySchedule
import com.falcon.neruwa.model.LearningCard
import com.falcon.neruwa.model.Mood
import com.falcon.neruwa.model.PvtResult
import com.falcon.neruwa.model.SharePost
import com.falcon.neruwa.model.SleepRecord
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDate

class NeruwaRepository(context: Context) {
    private val preferences = context.getSharedPreferences("neruwa_android", Context.MODE_PRIVATE)

    val sleepRecords = mutableStateListOf<SleepRecord>()
    val learningCards = mutableStateListOf<LearningCard>()
    val pvtResults = mutableStateListOf<PvtResult>()
    val sharePosts = mutableStateListOf<SharePost>()

    var targetMinutes by mutableStateOf(preferences.getInt(KEY_TARGET, 480))
        private set
    var schedule by mutableStateOf(
        DailySchedule(
            morningStartMinutes = preferences.getInt(KEY_MORNING_START, 4 * 60),
            nightStartMinutes = preferences.getInt(KEY_NIGHT_START, 19 * 60)
        )
    )
        private set
    var defaultVisibility by mutableStateOf(preferences.getString(KEY_VISIBILITY, "みんな") ?: "みんな")
        private set
    var reminderCount by mutableStateOf(preferences.getInt(KEY_REMINDER_COUNT, 3))
        private set
    var sleepTimerStartMillis by mutableLongStateOf(preferences.getLong(KEY_TIMER_START, 0L))
        private set
    var latestJournal by mutableStateOf(preferences.getString(KEY_JOURNAL, "") ?: "")
        private set
    var tomorrowTasks by mutableStateOf(preferences.getString(KEY_TASKS, "") ?: "")
        private set

    init {
        loadAll()
        if (learningCards.isEmpty()) {
            learningCards.addAll(defaultCards())
            persistCards()
        }
        if (sharePosts.isEmpty()) {
            sharePosts.addAll(samplePosts())
        }
    }

    fun updateTarget(minutes: Int) {
        targetMinutes = minutes.coerceIn(360, 600)
        preferences.edit().putInt(KEY_TARGET, targetMinutes).apply()
    }

    fun updateSchedule(newSchedule: DailySchedule) {
        schedule = newSchedule
        preferences.edit()
            .putInt(KEY_MORNING_START, newSchedule.morningStartMinutes)
            .putInt(KEY_NIGHT_START, newSchedule.nightStartMinutes)
            .apply()
    }

    fun updateVisibility(value: String) {
        defaultVisibility = value
        preferences.edit().putString(KEY_VISIBILITY, value).apply()
    }

    fun updateReminderCount(value: Int) {
        reminderCount = value.coerceIn(0, 5)
        preferences.edit().putInt(KEY_REMINDER_COUNT, reminderCount).apply()
    }

    fun saveJournal(journal: String, tasks: String) {
        latestJournal = journal
        tomorrowTasks = tasks
        preferences.edit().putString(KEY_JOURNAL, journal).putString(KEY_TASKS, tasks).apply()
    }

    fun startSleepTimer() {
        if (sleepTimerStartMillis == 0L) {
            sleepTimerStartMillis = System.currentTimeMillis()
            preferences.edit().putLong(KEY_TIMER_START, sleepTimerStartMillis).apply()
        }
    }

    fun cancelSleepTimer() {
        sleepTimerStartMillis = 0L
        preferences.edit().remove(KEY_TIMER_START).apply()
    }

    fun finishSleepTimer(): SleepRecord? {
        val start = sleepTimerStartMillis
        if (start == 0L) return null
        val end = System.currentTimeMillis().coerceAtLeast(start + 60_000L)
        val record = SleepRecord(
            bedtimeMillis = start,
            wakeMillis = end,
            targetMinutes = targetMinutes,
            source = "タイマー"
        )
        sleepRecords.add(record)
        persistSleepRecords()
        cancelSleepTimer()
        return record
    }

    fun addManualSleep(bedtimeMillis: Long, wakeMillis: Long) {
        sleepRecords.add(
            SleepRecord(
                bedtimeMillis = bedtimeMillis,
                wakeMillis = wakeMillis,
                targetMinutes = targetMinutes,
                source = "手入力"
            )
        )
        persistSleepRecords()
    }

    fun setMood(recordId: String, mood: Mood) {
        val index = sleepRecords.indexOfFirst { it.id == recordId }
        if (index >= 0) {
            sleepRecords[index] = sleepRecords[index].copy(mood = mood)
            persistSleepRecords()
        }
    }

    fun latestRecordWithoutMood(): SleepRecord? = sleepRecords
        .filter { it.mood == null }
        .maxByOrNull { it.wakeMillis }

    fun addCard(card: LearningCard) {
        learningCards.add(card)
        persistCards()
    }

    fun importCsv(csv: String, fallbackFolder: String = "インポート") : Int {
        val rows = csv.lineSequence().filter { it.isNotBlank() }.toList()
        if (rows.isEmpty()) return 0
        val header = rows.first().lowercase()
        val start = if ("prompt" in header || "問題" in header || "front" in header) 1 else 0
        var count = 0
        rows.drop(start).forEach { row ->
            val columns = parseCsvRow(row)
            if (columns.size >= 2 && columns[0].isNotBlank() && columns[1].isNotBlank()) {
                learningCards.add(
                    LearningCard(
                        prompt = columns[0].trim(),
                        answer = columns[1].trim(),
                        speech = columns.getOrNull(2)?.trim().takeUnless { it.isNullOrBlank() } ?: columns[1].trim(),
                        language = columns.getOrNull(3)?.trim().takeUnless { it.isNullOrBlank() } ?: "ja-JP",
                        folder = columns.getOrNull(4)?.trim().takeUnless { it.isNullOrBlank() } ?: fallbackFolder
                    )
                )
                count += 1
            }
        }
        if (count > 0) persistCards()
        return count
    }

    fun addPvtResult(result: PvtResult) {
        pvtResults.add(result)
        persistPvtResults()
    }

    fun addSharePost(message: String, mood: Mood?, visibility: String) {
        val latest = sleepRecords.maxByOrNull { it.wakeMillis }
        sharePosts.add(
            0,
            SharePost(
                author = "自分",
                sleepMinutes = latest?.durationMinutes ?: 0,
                mood = mood,
                message = message,
                visibility = visibility
            )
        )
        persistPosts()
    }

    fun shouldStartFlow(period: DailyPeriod, date: LocalDate = LocalDate.now()): Boolean {
        val key = if (period == DailyPeriod.MORNING) KEY_LAST_MORNING else KEY_LAST_NIGHT
        return preferences.getString(key, null) != date.toString()
    }

    fun completeFlow(period: DailyPeriod, date: LocalDate = LocalDate.now()) {
        val key = if (period == DailyPeriod.MORNING) KEY_LAST_MORNING else KEY_LAST_NIGHT
        preferences.edit().putString(key, date.toString()).apply()
    }

    fun resetFlow(period: DailyPeriod) {
        val key = if (period == DailyPeriod.MORNING) KEY_LAST_MORNING else KEY_LAST_NIGHT
        preferences.edit().remove(key).apply()
    }

    private fun loadAll() {
        runCatching { JSONArray(preferences.getString(KEY_SLEEP_RECORDS, "[]")) }.getOrNull()?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                sleepRecords.add(
                    SleepRecord(
                        id = item.getString("id"),
                        bedtimeMillis = item.getLong("bedtime"),
                        wakeMillis = item.getLong("wake"),
                        targetMinutes = item.optInt("target", 480),
                        mood = item.optString("mood").takeIf { it.isNotBlank() }?.let(Mood::valueOf),
                        source = item.optString("source", "手入力")
                    )
                )
            }
        }
        runCatching { JSONArray(preferences.getString(KEY_CARDS, "[]")) }.getOrNull()?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                val dots = item.optJSONArray("dots") ?: JSONArray()
                learningCards.add(
                    LearningCard(
                        id = item.getString("id"),
                        prompt = item.getString("prompt"),
                        answer = item.getString("answer"),
                        speech = item.optString("speech", item.getString("answer")),
                        language = item.optString("language", "ja-JP"),
                        folder = item.optString("folder", "点字"),
                        brailleDots = List(dots.length()) { dots.getInt(it) }
                    )
                )
            }
        }
        runCatching { JSONArray(preferences.getString(KEY_PVT_RESULTS, "[]")) }.getOrNull()?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                pvtResults.add(
                    PvtResult(
                        id = item.getString("id"),
                        measuredAtMillis = item.getLong("at"),
                        averageReactionMillis = item.getInt("average"),
                        lapses = item.getInt("lapses"),
                        falseStarts = item.getInt("falseStarts")
                    )
                )
            }
        }
        runCatching { JSONArray(preferences.getString(KEY_POSTS, "[]")) }.getOrNull()?.let { array ->
            repeat(array.length()) { index ->
                val item = array.getJSONObject(index)
                sharePosts.add(
                    SharePost(
                        id = item.getString("id"),
                        author = item.getString("author"),
                        createdAtMillis = item.getLong("at"),
                        sleepMinutes = item.getInt("sleep"),
                        mood = item.optString("mood").takeIf { it.isNotBlank() }?.let(Mood::valueOf),
                        message = item.getString("message"),
                        visibility = item.optString("visibility", "みんな")
                    )
                )
            }
        }
    }

    private fun persistSleepRecords() = preferences.edit().putString(
        KEY_SLEEP_RECORDS,
        JSONArray().apply {
            sleepRecords.forEach { record ->
                put(JSONObject().apply {
                    put("id", record.id)
                    put("bedtime", record.bedtimeMillis)
                    put("wake", record.wakeMillis)
                    put("target", record.targetMinutes)
                    put("mood", record.mood?.name ?: "")
                    put("source", record.source)
                })
            }
        }.toString()
    ).apply()

    private fun persistCards() = preferences.edit().putString(
        KEY_CARDS,
        JSONArray().apply {
            learningCards.forEach { card ->
                put(JSONObject().apply {
                    put("id", card.id)
                    put("prompt", card.prompt)
                    put("answer", card.answer)
                    put("speech", card.speech)
                    put("language", card.language)
                    put("folder", card.folder)
                    put("dots", JSONArray(card.brailleDots))
                })
            }
        }.toString()
    ).apply()

    private fun persistPvtResults() = preferences.edit().putString(
        KEY_PVT_RESULTS,
        JSONArray().apply {
            pvtResults.forEach { result ->
                put(JSONObject().apply {
                    put("id", result.id)
                    put("at", result.measuredAtMillis)
                    put("average", result.averageReactionMillis)
                    put("lapses", result.lapses)
                    put("falseStarts", result.falseStarts)
                })
            }
        }.toString()
    ).apply()

    private fun persistPosts() = preferences.edit().putString(
        KEY_POSTS,
        JSONArray().apply {
            sharePosts.filter { it.author == "自分" }.forEach { post ->
                put(JSONObject().apply {
                    put("id", post.id)
                    put("author", post.author)
                    put("at", post.createdAtMillis)
                    put("sleep", post.sleepMinutes)
                    put("mood", post.mood?.name ?: "")
                    put("message", post.message)
                    put("visibility", post.visibility)
                })
            }
        }.toString()
    ).apply()

    private fun parseCsvRow(row: String): List<String> {
        val result = mutableListOf<String>()
        val current = StringBuilder()
        var quoted = false
        var index = 0
        while (index < row.length) {
            val char = row[index]
            when {
                char == '"' && quoted && index + 1 < row.length && row[index + 1] == '"' -> {
                    current.append('"')
                    index += 1
                }
                char == '"' -> quoted = !quoted
                (char == ',' || char == '\t' || char == ';') && !quoted -> {
                    result.add(current.toString())
                    current.clear()
                }
                else -> current.append(char)
            }
            index += 1
        }
        result.add(current.toString())
        return result
    }

    private fun defaultCards() = listOf(
        LearningCard(prompt = "あ行", answer = "あ", speech = "あ", brailleDots = listOf(1)),
        LearningCard(prompt = "か行", answer = "か", speech = "か", brailleDots = listOf(1, 6)),
        LearningCard(prompt = "Apple", answer = "りんご", speech = "Apple", language = "en-US", folder = "英単語"),
        LearningCard(prompt = "Sleep", answer = "睡眠", speech = "Sleep", language = "en-US", folder = "英単語")
    )

    private fun samplePosts() = listOf(
        SharePost(author = "sora", sleepMinutes = 440, mood = Mood.GOOD, message = "昨日より少し早く眠れました"),
        SharePost(author = "mio", sleepMinutes = 505, mood = Mood.GREAT, message = "朝がすっきり。今日も続けたい")
    )

    companion object {
        private const val KEY_SLEEP_RECORDS = "sleep_records"
        private const val KEY_CARDS = "learning_cards"
        private const val KEY_PVT_RESULTS = "pvt_results"
        private const val KEY_POSTS = "share_posts"
        private const val KEY_TARGET = "target_minutes"
        private const val KEY_MORNING_START = "morning_start"
        private const val KEY_NIGHT_START = "night_start"
        private const val KEY_VISIBILITY = "visibility"
        private const val KEY_REMINDER_COUNT = "reminder_count"
        private const val KEY_TIMER_START = "timer_start"
        private const val KEY_JOURNAL = "journal"
        private const val KEY_TASKS = "tomorrow_tasks"
        private const val KEY_LAST_MORNING = "last_morning_flow"
        private const val KEY_LAST_NIGHT = "last_night_flow"
    }
}
