package com.kayan.net_app

import android.content.Context

/**
 * Durable inbox for inbound SMS so messages are not lost when Flutter
 * EventChannel is not listening (app killed / process not ready).
 *
 * هذا الصنف طبقة أندرويد فقط (SharedPreferences). كل منطق الصندوق — الترتيب،
 * والتأكيد (ack)، وسقف الحجم، والتعافي من حمولة تالفة — في [SmsInboxQueue]
 * ليُختبر على JVM بلا جهاز ولا محاكي (see SmsInboxQueueTest).
 */
internal class SmsInboxStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val queue = SmsInboxQueue(
        readRaw = { prefs.getString(KEY_QUEUE, null) },
        writeRaw = { prefs.edit().putString(KEY_QUEUE, it).apply() },
    )

    fun append(sender: String, body: String, timestampMillis: Long): PendingSms =
        queue.append(sender, body, timestampMillis)

    fun peek(limit: Int = SmsInboxQueue.MAX_ITEMS): List<PendingSms> = queue.peek(limit)

    fun ack(ids: Set<String>) = queue.ack(ids)

    companion object {
        private const val PREFS = "net_sms_inbox"
        private const val KEY_QUEUE = "queue"
    }
}
