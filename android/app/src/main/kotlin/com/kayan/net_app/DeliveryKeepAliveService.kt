package com.kayan.net_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * خدمة أمامية تُبقي عملية التطبيق حيّة ومُستيقظة حتى تستمر حلقة التسليم في Dart
 * (مؤقّت كل 3 ثوانٍ في `AppContainer`) بالعمل والواجهة في الخلفية أو مغلقة.
 *
 * بلا هذه الخدمة يصبح التطبيق «مخزّناً» (cached) بعد مغادرة الواجهة، وأندرويد
 * يجمّد التطبيقات المخزّنة ثم يقتل العملية تحت ضغط الذاكرة — فيتوقف إرسال قسيمة
 * العميل بعد بيع مُلتزم ومعالج (وهو الخلل الموثّق في
 * docs/commercial-qa-certification-2026-09-24.md §7-1).
 *
 * الوارد لا يعتمد على هذه الخدمة: [SmsReceiver] يحفظ الرسالة في [SmsInboxStore]
 * ثم تُعالَج عند عودة الحلقة. أما الصادر (قسيمة/تأكيد POS) فيحتاج بقاء العملية.
 *
 * القرار في [DeliveryKeepAlivePolicy] — منطق خالص مُختبَر على JVM.
 */
class DeliveryKeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            DeliveryKeepAliveEventStore.record(this, DeliveryKeepAliveEvent.STOPPED, "app_request")
            stopForegroundAndSelf()
            return START_NOT_STICKY
        }
        // النظام قد يعيد تشغيل الخدمة (START_STICKY) بعد قتل العملية. لا نعيد
        // الحكم على صلاحيات المشغّل هنا: طلب النظام ليس قراراً بشرياً، والإبقاء
        // على العملية حيّة يخدم الاسترداد. أما إيقافها فيأتي من التطبيق صراحةً.
        return try {
            startForeground(NOTIFICATION_ID, buildNotification())
            running = true
            lastStartAttemptAtMillis = System.currentTimeMillis()
            DeliveryKeepAliveEventStore.record(
                this,
                DeliveryKeepAliveEvent.STARTED,
                "foreground=specialUse",
            )
            START_STICKY
        } catch (e: Exception) {
            // مثلاً منع النظام بدء خدمة أمامية، أو تعطيل الإشعارات في بعض الواجهات.
            DeliveryKeepAliveEventStore.record(
                this,
                DeliveryKeepAliveEvent.START_REJECTED,
                e.javaClass.simpleName,
            )
            Log.w(TAG, "startForeground rejected: ${e.message}")
            stopSelf()
            START_NOT_STICKY
        }
    }

    /**
     * WP-9 / H1 — Android 15 ينادي `onTimeout` عند انتهاء حد النوع الأمامي.
     * لو تركناه بلا معالجة يمرشح التطبيق إلى حالة «لا يستجيب»، وهو الأقرب
     * لوصف المشكلة «بعد ساعات». المعالجة: توقف نظيف وتسجيل الحدث
     * وجدولة إعادة تشغيل مؤجلة بمسار مسموح.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        handleTimeout("fgsType=$fgsType")
    }

    /** النسخة الأقدم من النداء (API 34). */
    override fun onTimeout(startId: Int) {
        handleTimeout("legacy")
    }

    private fun handleTimeout(detail: String) {
        DeliveryKeepAliveEventStore.record(this, DeliveryKeepAliveEvent.TIMEOUT, detail)
        stopForegroundAndSelf()
        if (DeliveryKeepAlivePolicy.shouldRestartAfterTimeout(smsPermissionsGranted(applicationContext))) {
            KeepAliveRestartScheduler.schedule(applicationContext)
        }
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun stopForegroundAndSelf() {
        try {
            // minSdk = 24 في هذا المشروع، فهذا الثابت متاح دائمًا.
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (e: Exception) {
            Log.w(TAG, "stopForeground failed: ${e.message}")
        }
        stopSelf()
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val launch = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val mutability = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or mutability,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_stock)
            .setContentTitle(NOTIFICATION_TITLE)
            .setContentText(NOTIFICATION_BODY)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setSilent(true)
            .setContentIntent(contentIntent)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            NOTIFICATION_TITLE,
            // بلا صوت/اهتزاز: إشعار حالة فقط، فلا يُزعج المشغّل في كل تشغيل.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "يبقي تسليم الكروت والتحويلات يعمل والواجهة مغلقة"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val TAG = "NetDeliveryKeepAlive"

        const val ACTION_START = "com.kayan.net.keepalive.START"
        const val ACTION_STOP = "com.kayan.net.keepalive.STOP"
        const val CHANNEL_ID = "krotak_delivery_keepalive"
        const val NOTIFICATION_ID = 7002
        const val NOTIFICATION_TITLE = "تسليم الكروت يعمل"
        const val NOTIFICATION_BODY = "التطبيق يتابع إرسال الكروت والتحويلات في الخلفية"

        /** هل الخدمة تعمل الآن في هذه العملية. */
        @Volatile
        private var running = false

        /** آخر محاولة تشغيل — يُستخدم مع [DeliveryKeepAlivePolicy.shouldThrottleStart]. */
        @Volatile
        private var lastStartAttemptAtMillis: Long? = null

        fun isRunning(): Boolean = running

        /** نفس شرط الواجهة: قراءة وإرسال الرسائل معاً. */
        fun smsPermissionsGranted(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECEIVE_SMS) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(context, android.Manifest.permission.READ_SMS) ==
                PackageManager.PERMISSION_GRANTED &&
                ContextCompat.checkSelfPermission(context, android.Manifest.permission.SEND_SMS) ==
                PackageManager.PERMISSION_GRANTED

        /**
         * يطلب تشغيل الخدمة وفق [DeliveryKeepAlivePolicy].
         *
         * كل النداءات آمنة من الخلفية: النظام على Android 12+ يرفض بدء خدمة أمامية
         * من سياق غير مسموح، فالمحاولة تُبتلع وتُسجَّل بدل أن تُسقط التطبيق (وإلا
         * لأسقطت رسالة SMS واردة التطبيق قبل تحليلها).
         *
         * @return هل أصبحت الخدمة مطلوبة/عاملة بعد النداء.
         */
        fun requestStart(
            context: Context,
            smsPermissionsGranted: Boolean,
            nowMillis: Long = System.currentTimeMillis(),
        ): Boolean {
            val action = DeliveryKeepAlivePolicy.decide(smsPermissionsGranted, running)
            if (action == DeliveryKeepAlivePolicy.Action.NOOP) return running
            if (action == DeliveryKeepAlivePolicy.Action.STOP) {
                requestStop(context)
                return false
            }
            if (DeliveryKeepAlivePolicy.shouldThrottleStart(lastStartAttemptAtMillis, nowMillis)) {
                return running
            }
            lastStartAttemptAtMillis = nowMillis
            return try {
                val intent = Intent(context, DeliveryKeepAliveService::class.java)
                    .setAction(ACTION_START)
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (e: Exception) {
                Log.w(TAG, "keep-alive start rejected: ${e.message}")
                false
            }
        }

        /** إيقاف صريح (سحب صلاحية SMS، أو قرار المشغّل). */
        fun requestStop(context: Context): Boolean {
            return try {
                context.stopService(Intent(context, DeliveryKeepAliveService::class.java))
                false
            } catch (e: Exception) {
                Log.w(TAG, "keep-alive stop failed: ${e.message}")
                running
            }
        }
    }
}
