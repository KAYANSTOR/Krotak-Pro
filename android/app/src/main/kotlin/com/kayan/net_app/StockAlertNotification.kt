package com.kayan.net_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * إشعار أندرويد «حي» لتنبيه انخفاض مخزون الكروت.
 *
 * - مستمر: `setOngoing(true)` و`setAutoCancel(false)` فلا يُسحب ولا يُغلق من
 *   المستخدم، ويبقى في شريط الإشعارات حتى يُلغى صراحةً من التطبيق بعد إعادة
 *   تعبئة المخزون فوق العتبة.
 * - `setOnlyAlertOnce(true)` حتى لا يصدر صوت/اهتزاز مع كل تحديث للنص.
 * - النص الأخير يُحفظ في SharedPreferences ليُعاد نشره بعد إعادة تشغيل الهاتف
 *   في الحالات التي لا يبدأ فيها التطبيق تلقائياً (بعض الشركات تمنع ذلك).
 *
 * القناة تُنشأ مرة واحدة: تعديل نص القناة أو أهميتها لاحقاً لا يؤثر على
 * المستخدمين الحاليين، لذلك القيمة الافتراضية محسوبة من البداية.
 */
object StockAlertNotification {
    private const val TAG = "NetStockAlert"
    const val CHANNEL_ID = "krotak_stock_alert"
    private const val NOTIFICATION_ID = 7001
    private const val PREFS = "krotak_stock_alert_prefs"
    private const val KEY_TITLE = "title"
    private const val KEY_BODY = "body"

    /** ينشر التنبيه (ويحفظ نصه لإعادة نشره عند الحاجة). */
    fun show(context: Context, title: String, body: String) {
        val cleanTitle = title.trim()
        val cleanBody = body.trim()
        if (cleanTitle.isEmpty() || cleanBody.isEmpty()) return
        store(context, cleanTitle, cleanBody)
        post(context, cleanTitle, cleanBody)
    }

    /** يلغي التنبيه وينسى نصه — يُستدعى فقط عند إعادة تعبئة المخزون. */
    fun clear(context: Context) {
        store(context, "", "")
        try {
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.w(TAG, "failed to cancel stock alert: ${e.message}")
        }
    }

    /** يعيد نشر آخر تنبيه محفوظ بعد إعادة تشغيل الجهاز. */
    fun repostIfActive(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val title = prefs.getString(KEY_TITLE, null)?.trim().orEmpty()
        val body = prefs.getString(KEY_BODY, null)?.trim().orEmpty()
        if (title.isEmpty() || body.isEmpty()) return
        post(context, title, body)
    }

    private fun post(context: Context, title: String, body: String) {
        try {
            ensureChannel(context)
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            val mutability = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
            val contentIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or mutability,
            )
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                // أيقونة الحالة: مونوغرام كروتك (ic_stat_stock → mono art)، وليس مثلث تحذير.
                .setSmallIcon(R.drawable.ic_stat_stock)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setShowWhen(true)
                .setContentIntent(contentIntent)
            // أيقونة كبيرة من الصور (لا تُستخدم @mipmap/ic_launcher لأنها أيقونة
            // متكيّفة XML ولا يمكن فكّها كصورة نقطية).
            val large = BitmapFactory.decodeResource(context.resources, R.drawable.ic_notif_large)
            if (large != null) builder.setLargeIcon(large)
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            Log.w(TAG, "failed to post stock alert: ${e.message}")
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "تنبيه المخزون",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "إشعار حي يبقى ظاهراً حتى إعادة تعبئة مخزون الكروت"
            setShowBadge(true)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun store(context: Context, title: String, body: String) {
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_TITLE, title)
                .putString(KEY_BODY, body)
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "failed to persist stock alert: ${e.message}")
        }
    }
}
