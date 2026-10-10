package com.kayan.net_app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * WP-9 — ترميز وفك ترميز سجل أحداث خدمة الحفاظ (الدليل).
 *
 * ما لا يُثبته هذا الاختبار: أن SharedPreferences تكتب فعلًا على جهاز، وأن
 * النظام ينادي `onTimeout` — وهما بندا جهاز (D11).
 */
class DeliveryKeepAliveEventsTest {

    @Test
    fun `an event round trips with its timestamp and detail`() {
        val raw = DeliveryKeepAliveEventFormat.encode(
            atMillis = 1_700_000_000_000L,
            event = DeliveryKeepAliveEvent.TIMEOUT,
            detail = "fgsType=8",
        )
        val entry = DeliveryKeepAliveEventFormat.decode(raw)
        assertNotNull(entry)
        assertEquals(1_700_000_000_000L, entry.atMillis)
        assertEquals(DeliveryKeepAliveEvent.TIMEOUT, entry.event)
        assertEquals("fgsType=8", entry.detail)
    }

    @Test
    fun `arabic details survive the round trip`() {
        val entry = DeliveryKeepAliveEventFormat.decode(
            DeliveryKeepAliveEventFormat.encode(
                atMillis = 42L,
                event = DeliveryKeepAliveEvent.START_REJECTED,
                detail = "رفض النظام البدء",
            ),
        )
        assertNotNull(entry)
        assertEquals("رفض النظام البدء", entry.detail)
    }

    @Test
    fun `the separator inside a detail does not break decoding`() {
        val entry = DeliveryKeepAliveEventFormat.decode(
            DeliveryKeepAliveEventFormat.encode(1L, DeliveryKeepAliveEvent.STARTED, "a|b"),
        )
        assertNotNull(entry)
        assertEquals(DeliveryKeepAliveEvent.STARTED, entry.event)
        assertEquals("a/b", entry.detail)
    }

    @Test
    fun `malformed lines are ignored instead of crashing the screen`() {
        assertNull(DeliveryKeepAliveEventFormat.decode(""))
        assertNull(DeliveryKeepAliveEventFormat.decode(null))
        assertNull(DeliveryKeepAliveEventFormat.decode("not-a-record"))
        assertNull(DeliveryKeepAliveEventFormat.decode("1000|"))
        assertTrue(DeliveryKeepAliveEventFormat.parseAll(listOf("junk", "5|started|")).isEmpty())
    }

    @Test
    fun `the log keeps only the newest entries`() {
        var entries = emptyList<String>()
        for (index in 1..5) {
            entries = DeliveryKeepAliveEventFormat.append(
                entries,
                DeliveryKeepAliveEventFormat.encode(index.toLong(), DeliveryKeepAliveEvent.STARTED, "$index"),
                maxEntries = 3,
            )
        }
        assertEquals(3, entries.size)
        val parsed = DeliveryKeepAliveEventFormat.parseAll(entries)
        assertEquals(listOf(5L, 4L, 3L), parsed.map { it.atMillis })
    }

    @Test
    fun `a non positive limit falls back to the documented maximum`() {
        val entries = DeliveryKeepAliveEventFormat.append(emptyList(), "1|started|", maxEntries = 0)
        assertEquals(1, entries.size)
        assertEquals(40, DeliveryKeepAliveEventFormat.MAX_ENTRIES)
    }
}
