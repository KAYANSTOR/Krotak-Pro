package com.kayan.net_app

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** A single inbound SMS waiting for the Flutter layer to consume it. */
internal data class PendingSms(
    val id: String,
    val sender: String,
    val body: String,
    val timestampMillis: Long,
)

/**
 * المنطق الحقيقي لصندوق الرسائل الواردة الدائم — بدون أي نوع من أنواع Android.
 *
 * كل ما يمكن أن يُفسد الصندوق موجود هنا: الترتيب، والتأكيد (ack)، وسقف الحجم،
 * والتعافي من حمولة تالفة. فصل هذا عن [SmsInboxStore] يجعل نفس الكود قابلًا
 * للاختبار على JVM بلا جهاز ولا محاكي ولا Robolectric.
 *
 * @param readRaw  يقرأ الحمولة الخام المخزّنة (null = لا شيء محفوظ).
 * @param writeRaw يكتب الحمولة الخام (JSON).
 */
internal class SmsInboxQueue(
    private val readRaw: () -> String?,
    private val writeRaw: (String) -> Unit,
) {
    // المُستقبِل (BroadcastReceiver) وخيط الواجهة قد يكتبان في نفس اللحظة.
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
        val raw = readRaw() ?: return emptyList()
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
            // حمولة تالفة لا يجوز أن تُفقد الرسائل القادمة بعدها: نعتبرها فارغة
            // ويُعاد بناء المخزن عند أول append.
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
        writeRaw(array.toString())
    }

    companion object {
        /** أقصى عدد رسائل محفوظة — الأقدم يُسقط عند التجاوز. */
        const val MAX_ITEMS = 200
    }
}
