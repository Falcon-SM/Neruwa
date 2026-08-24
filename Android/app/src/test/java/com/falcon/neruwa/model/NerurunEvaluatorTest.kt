package com.falcon.neruwa.model

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class NerurunEvaluatorTest {
    private val zone = ZoneId.systemDefault()
    private val today = LocalDate.of(2026, 8, 24)

    @Test
    fun noRecordsIsNormal() {
        assertEquals(
            NerurunCondition.NORMAL,
            NerurunEvaluator.evaluate(emptyList(), today = today).condition
        )
    }

    @Test
    fun shortSleepIsExhausted() {
        val record = record(today, minutes = 240, mood = Mood.BAD)
        assertEquals(
            NerurunCondition.EXHAUSTED,
            NerurunEvaluator.evaluate(listOf(record), today = today).condition
        )
    }

    @Test
    fun slightlyShortSleepIsDiscouraged() {
        val record = record(today, minutes = 390, mood = Mood.FLAT)
        assertEquals(
            NerurunCondition.DISCOURAGED,
            NerurunEvaluator.evaluate(listOf(record), today = today).condition
        )
    }

    @Test
    fun stableWeekAddsCompanions() {
        val records = (0L..6L).map { offset ->
            record(today.minusDays(offset), minutes = 480, mood = Mood.GREAT)
        }
        val status = NerurunEvaluator.evaluate(records, today = today)
        assertEquals(NerurunCondition.THRIVING, status.condition)
        assertEquals(2, status.companionCount)
    }

    private fun record(date: LocalDate, minutes: Int, mood: Mood): SleepRecord {
        val wake = date.atTime(7, 0).atZone(zone).toInstant().toEpochMilli()
        return SleepRecord(
            bedtimeMillis = wake - minutes * 60_000L,
            wakeMillis = wake,
            targetMinutes = 480,
            mood = mood
        )
    }
}
