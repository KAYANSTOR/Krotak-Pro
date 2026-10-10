package com.kayan.net_app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * اختبار JVM لمنطق قرار خدمة الخلفية — نفس الكود الذي تستخدمه
 * [DeliveryKeepAliveService] و[MainActivity.wireKeepAlive] و[SmsReceiver] فعلياً.
 *
 * ما لا يُثبته هذا الاختبار ويبقى جهازياً: أن النظام يقبل الخدمة فعلاً، وأن
 * العملية لا تُقتل، وأن حلقة Dart تُستأنف بعد قتل النظام لها.
 */
class DeliveryKeepAlivePolicyTest {

    @Test
    fun `starts when sms permissions are granted and the service is not running`() {
        assertEquals(
            DeliveryKeepAlivePolicy.Action.START,
            DeliveryKeepAlivePolicy.decide(smsPermissionsGranted = true, running = false),
        )
    }

    @Test
    fun `does not restart an already running service`() {
        assertEquals(
            DeliveryKeepAlivePolicy.Action.NOOP,
            DeliveryKeepAlivePolicy.decide(smsPermissionsGranted = true, running = true),
        )
    }

    @Test
    fun `stops a running service once sms permissions are revoked`() {
        assertEquals(
            DeliveryKeepAlivePolicy.Action.STOP,
            DeliveryKeepAlivePolicy.decide(smsPermissionsGranted = false, running = true),
        )
    }

    @Test
    fun `does nothing without sms permissions when nothing is running`() {
        assertEquals(
            DeliveryKeepAlivePolicy.Action.NOOP,
            DeliveryKeepAlivePolicy.decide(smsPermissionsGranted = false, running = false),
        )
    }

    @Test
    fun `a first start attempt is never throttled`() {
        assertFalse(
            DeliveryKeepAlivePolicy.shouldThrottleStart(
                lastAttemptAtMillis = null,
                nowMillis = 1_000L,
            ),
        )
    }

    @Test
    fun `an immediate second attempt is throttled`() {
        assertTrue(
            DeliveryKeepAlivePolicy.shouldThrottleStart(
                lastAttemptAtMillis = 10_000L,
                nowMillis = 10_000L + DeliveryKeepAlivePolicy.MIN_START_INTERVAL_MILLIS - 1,
            ),
        )
    }

    @Test
    fun `an attempt after the minimum interval is allowed again`() {
        assertFalse(
            DeliveryKeepAlivePolicy.shouldThrottleStart(
                lastAttemptAtMillis = 10_000L,
                nowMillis = 10_000L + DeliveryKeepAlivePolicy.MIN_START_INTERVAL_MILLIS,
            ),
        )
    }

    @Test
    fun `a clock that jumped backwards does not freeze future attempts`() {
        // تصحيح وقت الجهاز لا يجوز أن يمنع التشغيل إلى الأبد.
        assertFalse(
            DeliveryKeepAlivePolicy.shouldThrottleStart(
                lastAttemptAtMillis = 50_000L,
                nowMillis = 1_000L,
            ),
        )
    }

    @Test
    fun `after a system timeout the restart is scheduled only with sms permissions`() {
        // WP-9 / H1: مهلة النظام تنتهي فنُجدول إعادة تشغيل،
        // وبلا صلاحية SMS لا وظيفة للخدمة فلا نُبقي إشعارًا دائمًا.
        assertTrue(DeliveryKeepAlivePolicy.shouldRestartAfterTimeout(smsPermissionsGranted = true))
        assertFalse(DeliveryKeepAlivePolicy.shouldRestartAfterTimeout(smsPermissionsGranted = false))
    }

    @Test
    fun `the timeout restart delay is one minute`() {
        assertEquals(60_000L, DeliveryKeepAlivePolicy.TIMEOUT_RESTART_DELAY_MILLIS)
    }

    @Test
    fun `the throttle window is five seconds by default`() {
        assertEquals(5_000L, DeliveryKeepAlivePolicy.MIN_START_INTERVAL_MILLIS)
        assertTrue(
            DeliveryKeepAlivePolicy.shouldThrottleStart(
                lastAttemptAtMillis = 0L,
                nowMillis = 4_999L,
            ),
        )
        assertFalse(
            DeliveryKeepAlivePolicy.shouldThrottleStart(
                lastAttemptAtMillis = 0L,
                nowMillis = 5_000L,
            ),
        )
    }
}
