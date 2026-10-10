package com.kayan.net_app

import android.content.Context
import android.util.Log

/**
 * مخزن دائم لأحداث خدمة الحفاظ على التسليم (WP-9).
 *
 * SharedPreferences لأنه ينجو من قتل العملية، ويُقرأ من شاشة
 * التحقق من الجهاز عبر قناة `com.kayan.net/diagnostics`. الترميز في
 * [DeliveryKeepAliveEventFormat] المُختبر على JVM.
 */
internal object DeliveryKeepAliveEventStore {
    private const val TAG = "NetKeepAliveEvents"
    private const val PREFS = "net_keepalive_events"
    private const val KEY_ENTRIES = "entries"
    private const val ENTRY_SEPARATOR = "\n"

    fun record(
        context: Context,
        event: String,
        detail: String = "",
        atMillis: Long = System.currentTimeMillis(),
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val ordered = DeliveryKeepAliveEventFormat.parseAll(readRaw(prefs))
                .sortedByDescending { it.atMillis }
                .map { DeliveryKeepAliveEventFormat.encode(it.atMillis, it.event, it.detail) }
            val next = DeliveryKeepAliveEventFormat.append(
                ordered,
                DeliveryKeepAliveEventFormat.encode(atMillis, event, detail),
            )
            prefs.edit().putString(KEY_ENTRIES, next.joinToString(ENTRY_SEPARATOR)).apply()
        } catch (e: Exception) {
            // تسجيل الدليل لا يجوز أن يُسقط الخدمة.
            Log.w(TAG, "record failed: ${e.message}")
        }
    }

    fun read(context: Context): List<DeliveryKeepAliveEventEntry> {
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            DeliveryKeepAliveEventFormat.parseAll(readRaw(prefs))
                .sortedByDescending { it.atMillis }
        } catch (e: Exception) {
            Log.w(TAG, "read failed: ${e.message}")
            emptyList()
        }
    }

    fun clear(context: Context) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_ENTRIES)
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "clear failed: ${e.message}")
        }
    }

    private fun readRaw(prefs: android.content.SharedPreferences): List<String> {
        val raw = prefs.getString(KEY_ENTRIES, "") ?: ""
        if (raw.isBlank()) return emptyList()
        return raw.split(ENTRY_SEPARATOR).filter { it.isNotBlank() }
    }
}
