package com.kayan.net_app

/**
 * قرار تشغيل خدمة الحفاظ على حياة عملية التسليم.
 *
 * منطق خالص بلا أي نوع من أنواع Android — مثل [SmsInboxQueue] — ليُختبر على JVM
 * بلا جهاز ولا محاكي (انظر DeliveryKeepAlivePolicyTest).
 *
 * سبب الوجود: حلقة التسليم في Dart (مؤقّت كل 3 ثوانٍ) تعمل في عملية التطبيق.
 * وأندرويد يجمّد التطبيقات المخزّنة (cached/frozen) أو يقتلها فلا تكتمل قسيمة
 * العميل بعد البيع. الخدمة الأمامية تُخرج العملية من حالة «مخزّن» فتبقى الحلقة
 * تعمل والواجهة مغلقة.
 */
internal object DeliveryKeepAlivePolicy {

    /**
     * أقل فاصل بين محاولتَي تشغيل متتاليتين.
     *
     * دورة الحياة تستدعي التشغيل عند كل عودة للتطبيق، ورسالة SMS واردة تستدعيه
     * أيضاً، فبلا هذا الحد تُرشّ طلبات `startForegroundService` بلا داعٍ (وربما
     * تُرفض من النظام فتلوّث السجل).
     */
    const val MIN_START_INTERVAL_MILLIS = 5_000L

    enum class Action { START, STOP, NOOP }

    /**
     * [smsPermissionsGranted] الخدمة موجودة لإكمال تسليم الرسائل عبر SMS؛ بلا
     * هذه الصلاحية لا يبقى إلا إشعار دائم بلا وظيفة، فنوقفها.
     * [running] هل الخدمة تعمل فعلًا الآن في هذه العملية.
     */
    fun decide(smsPermissionsGranted: Boolean, running: Boolean): Action = when {
        !smsPermissionsGranted -> if (running) Action.STOP else Action.NOOP
        running -> Action.NOOP
        else -> Action.START
    }

    /**
     * هل نُسقط محاولة التشغيل لجِدّتها؟
     *
     * رجوع الساعة للخلف (تصحيح وقت الجهاز) لا يجوز أن يجمّد المحاولات للأبد،
     * لذلك تُقبل المحاولة عند فاصل سالب.
     */
    fun shouldThrottleStart(
        lastAttemptAtMillis: Long?,
        nowMillis: Long,
        minIntervalMillis: Long = MIN_START_INTERVAL_MILLIS,
    ): Boolean {
        if (lastAttemptAtMillis == null) return false
        val elapsed = nowMillis - lastAttemptAtMillis
        if (elapsed < 0) return false
        return elapsed < minIntervalMillis
    }
}
