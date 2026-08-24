package com.falcon.neruwa.model

import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

object NerurunEvaluator {
    fun evaluate(
        records: List<SleepRecord>,
        fallbackTargetMinutes: Int = 480,
        today: LocalDate = LocalDate.now()
    ): NerurunStatus {
        val recent = records.sortedByDescending { it.wakeMillis }
        val latest = recent.firstOrNull()
            ?: return NerurunStatus(NerurunCondition.NORMAL)

        fun ratio(record: SleepRecord): Double {
            val target = record.targetMinutes.takeIf { it > 0 } ?: fallbackTargetMinutes
            return record.durationMinutes.toDouble() / target.coerceAtLeast(1)
        }

        val latestRatio = ratio(latest)
        val latestThree = recent.take(3)
        val recentAverage = latestThree.map(::ratio).average()
        val twoBadMoods = recent.take(2).size == 2 && recent.take(2).all { it.mood == Mood.BAD }

        if (latestRatio < 0.62 ||
            (latestThree.size >= 2 && recentAverage < 0.68) ||
            twoBadMoods
        ) {
            return NerurunStatus(NerurunCondition.EXHAUSTED)
        }

        val weekRecords = recent.filter {
            ChronoUnit.DAYS.between(it.wakeDate, today) in 0..7
        }
        val recordedDays = weekRecords.map { it.wakeDate }.toSet()
        val stableAverage = weekRecords.map(::ratio).takeIf { it.isNotEmpty() }?.average() ?: 0.0
        val positiveMoods = weekRecords.count { it.mood == Mood.GOOD || it.mood == Mood.GREAT }
        val hasBadMood = weekRecords.any { it.mood == Mood.BAD }

        if (recordedDays.size >= 5 && stableAverage >= 0.90 && positiveMoods >= 3 && !hasBadMood) {
            val streak = consecutiveDays(recent, today)
            return NerurunStatus(
                NerurunCondition.THRIVING,
                companionCount = (streak / 3).coerceIn(1, 3)
            )
        }

        val daysSinceLatest = ChronoUnit.DAYS.between(latest.wakeDate, today)
        if (latestRatio < 0.85 || latest.mood == Mood.BAD || latest.mood == Mood.FLAT || daysSinceLatest >= 2) {
            return NerurunStatus(NerurunCondition.DISCOURAGED)
        }
        return NerurunStatus(NerurunCondition.NORMAL)
    }

    private fun consecutiveDays(records: List<SleepRecord>, today: LocalDate): Int {
        val days = records.map { it.wakeDate }.toSet()
        var cursor = if (today in days) today else today.minusDays(1)
        var count = 0
        while (cursor in days) {
            count += 1
            cursor = cursor.minusDays(1)
        }
        return count
    }
}
