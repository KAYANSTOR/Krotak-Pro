package com.kayan.net_app

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class DailySummaryScheduleTest {
    @Test
    fun nextMidnightIsTheFollowingLocalDay() {
        val zone = ZoneId.of("Asia/Aden")
        val now = ZonedDateTime.of(2026, 10, 2, 9, 9, 0, 0, zone)
        val next = DailySummarySchedule.nextTriggerMillis(now)
        val scheduled = java.time.Instant.ofEpochMilli(next).atZone(zone)
        assertEquals(2026, scheduled.year)
        assertEquals(10, scheduled.monthValue)
        assertEquals(3, scheduled.dayOfMonth)
        assertEquals(0, scheduled.hour)
        assertEquals(0, scheduled.minute)
    }

    @Test
    fun exactlyMidnightStillSchedulesTheNextDay() {
        val zone = ZoneId.of("Asia/Aden")
        val now = ZonedDateTime.of(2026, 10, 2, 0, 0, 0, 0, zone)
        val next = DailySummarySchedule.nextTriggerMillis(now)
        val scheduled = java.time.Instant.ofEpochMilli(next).atZone(zone)
        assertEquals(3, scheduled.dayOfMonth)
        assertEquals(0, scheduled.hour)
    }
}
