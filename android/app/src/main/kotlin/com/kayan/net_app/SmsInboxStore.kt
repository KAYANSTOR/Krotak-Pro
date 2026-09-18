package com.kayan.net_app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal data class PendingSms(
    val id: String,
    val sender: String,
    val body: String,
    val timestampMillis: Long,
)

/**
 * Durable inbox for inbound SMS so messages are not lost when Flutter
 * EventChannel is not listening (app killed / process not ready).
 */
internal class SmsInboxStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    fun append(sender: String, body: String, timestampMillis: Long): PendingSms {
        val item = PendingSms(UUID.randomUUID().toString(), sender, body, timestampMillis)
        synchronized(lock) {
            val items = read().toMutableList()
            items.add(item)
            while (items.size > MAX_ITEMS) items.removeAt(0)
            write(items)
        }
        return item
    }

    fun peek(limit: Int = MAX_ITEMS): List<PendingSms> =
        synchronized(lock) { read().take(limit) }

    fun ack(ids: Set<String>) {
        if (ids.isEmpty()) return
        synchronized(lock) { write(read().filterNot { ids.contains(it.id) }) }
    }

    private fun read(): List<PendingSms> {
        val raw = prefs.getString(KEY_QUEUE, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    add(
                        PendingSms(
                            o.getString("id"),
                            o.getString("sender"),
                            o.getString("body"),
                            o.getLong("timestampMillis"),
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun write(items: List<PendingSms>) {
        val array = JSONArray()
        items.forEach { item ->
            array.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("sender", item.sender)
                    put("body", item.body)
                    put("timestampMillis", item.timestampMillis)
                },
            )
        }
        prefs.edit().putString(KEY_QUEUE, array.toString()).apply()
    }

    companion object {
        private const val PREFS = "net_sms_inbox"
        private const val KEY_QUEUE = "queue"
        private const val MAX_ITEMS = 200
    }
}
