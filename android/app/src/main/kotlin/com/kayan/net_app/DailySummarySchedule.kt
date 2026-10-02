package com.kayan.net_app

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Next local midnight for the POS daily summary alarm.
 * Pure so unit tests do not need an Android runtime.
 */
object DailySummarySchedule {
    fun nextTriggerMillis(nowMillis: Long, zone: ZoneId): Long {
        val current = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val nextMidnight = current.toLocalDate().plusDays(1).atStartOfDay(zone)
        return nextMidnight.toInstant().toEpochMilli()
    }

    fun nextTriggerMillis(now: ZonedDateTime): Long =
        nextTriggerMillis(now.toInstant().toEpochMilli(), now.zone)
}
