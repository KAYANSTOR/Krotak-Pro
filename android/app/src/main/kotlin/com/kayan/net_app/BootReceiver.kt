package com.kayan.net_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * After device boot / package replace:
 * 1) Persist recovery hint for Flutter resume path.
 * 2) Bring [MainActivity] up so background processing and recovery start
 *    without waiting for a manual open (user request).
 *
 * SMS still arrives via [SmsReceiver] independently of the UI process.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        Log.i(TAG, "boot/package event action=$action — recovery + auto-start")
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_PENDING_RECOVERY, true)
                .putLong(KEY_BOOT_AT, System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "failed to persist boot recovery hint: ${e.message}")
        }

        try {
            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra(EXTRA_FROM_BOOT, true)
            }
            context.startActivity(launch)
            Log.i(TAG, "MainActivity launched after $action")
        } catch (e: Exception) {
            // Some OEMs block background activity starts until autostart is allowed.
            Log.w(TAG, "auto-start MainActivity blocked: ${e.message}")
            // التطبيق لم يبدأ فلا يمكن مزامنة التنبيه من طبقة المجال — نُعيد نشر
            // آخر تنبيه مخزون محفوظ حتى لا يختفي من المستخدم بعد إعادة التشغيل.
            // يُصحَّح تلقائياً أول مرة يُفتح فيها التطبيق.
            StockAlertNotification.repostIfActive(context)
        }
    }

    companion object {
        private const val TAG = "NetBootReceiver"
        const val PREFS = "net_boot_prefs"
        const val KEY_PENDING_RECOVERY = "pending_recovery_after_boot"
        const val KEY_BOOT_AT = "last_boot_at_ms"
        const val EXTRA_FROM_BOOT = "net_from_boot"

        /** Called from MainActivity when Flutter engine is ready. */
        fun consumePendingRecovery(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val pending = prefs.getBoolean(KEY_PENDING_RECOVERY, false)
            if (pending) {
                prefs.edit().putBoolean(KEY_PENDING_RECOVERY, false).apply()
            }
            return pending
        }
    }
}
