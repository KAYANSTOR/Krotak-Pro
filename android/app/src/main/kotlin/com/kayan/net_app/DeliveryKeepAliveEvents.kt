package com.kayan.net_app

/**
 * WP-9 — أحداث خدمة الحفاظ على التسليم (الدليل المطلوب قبل أي إصلاح).
 *
 * السبب: الشكوى «التطبيق يتوقف بعد ساعات في الخلفية» لا تُحلّ بالتخمين،
 * فنُسجّل كل حدث بوقته (بدء/رفض/توقف/`onTimeout`/إعادة تشغيل) في
 * مخزن دائم يُعرض في شاشة التحقق من الجهاز بالعربية.
 */
internal object DeliveryKeepAliveEvent {
    const val START_REQUESTED = "start_requested"
    const val STARTED = "started"
    const val START_REJECTED = "start_rejected"
    const val STOPPED = "stopped"
    const val TIMEOUT = "timeout"
    const val RESTART_SCHEDULED = "restart_scheduled"
    const val RESTART_ATTEMPTED = "restart_attempted"
    const val BOOT_TRIGGER = "boot_trigger"
    const val SMS_TRIGGER = "sms_trigger"
}

/** حدث واحد بوقته وتفصيله. */
internal data class DeliveryKeepAliveEventEntry(
    val atMillis: Long,
    val event: String,
    val detail: String,
)

/**
 * ترميز وفك ترميز سجل الأحداث — منطق خالص بلا Android
 * ليُختبر على JVM (انظر DeliveryKeepAliveEventsTest).
 *
 * الصيغة: `atMillis|event|detail` واحد في السطر، والأحدث أولًا.
 * التفاصيل تُنزّف من محارف الفاصل حتى لا يُفسد السجل.
 */
internal object DeliveryKeepAliveEventFormat {
    const val MAX_ENTRIES = 40
    private const val SEPARATOR = '|'
    private const val UNKNOWN_TIME = 0L

    fun encode(atMillis: Long, event: String, detail: String = ""): String =
        "$atMillis$SEPARATOR$event$SEPARATOR${sanitize(detail)}"

    fun decode(raw: String?): DeliveryKeepAliveEventEntry? {
        if (raw.isNullOrBlank()) return null
        val parts = raw.split(SEPARATOR)
        if (parts.size < 2) return null
        val at = parts[0].toLongOrNull() ?: UNKNOWN_TIME
        val event = parts[1].trim()
        if (event.isEmpty()) return null
        val detail = if (parts.size > 2) parts.subList(2, parts.size).joinToString(SEPARATOR.toString()) else ""
        return DeliveryKeepAliveEventEntry(at, event, detail)
    }

    /** يُضاف الحدث الجديد في البداية مع تقليم الحجم. */
    fun append(
        existing: List<String>,
        entry: String,
        maxEntries: Int = MAX_ENTRIES,
    ): List<String> {
        val limit = if (maxEntries <= 0) MAX_ENTRIES else maxEntries
        val next = ArrayList<String>(existing.size + 1)
        next.add(entry)
        for (item in existing) {
            if (next.size >= limit) break
            next.add(item)
        }
        return next
    }

    /** يرجع الأحداث من الأحدث للأقدم. */
    fun parseAll(entries: List<String>): List<DeliveryKeepAliveEventEntry> =
        entries.mapNotNull { decode(it) }

    private fun sanitize(detail: String): String =
        detail.replace(SEPARATOR, '/').replace('\n', ' ').trim()
}
