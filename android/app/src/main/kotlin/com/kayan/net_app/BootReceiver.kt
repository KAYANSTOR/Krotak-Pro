package com.kayan.net_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Phase 5: after device boot, mark a flag so the next Flutter session runs
 * recovery/delivery worker promptly. SMS continues via [SmsReceiver] which is
 * registered independently of the Flutter process.
 *
 * Does **not** auto-open the UI (avoids intrusive launch on every reboot).
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        Log.i(TAG, "boot/package event action=$action — scheduling recovery hint")
        try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_PENDING_RECOVERY, true)
                .putLong(KEY_BOOT_AT, System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "failed to persist boot recovery hint: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "NetBootReceiver"
        const val PREFS = "net_boot_prefs"
        const val KEY_PENDING_RECOVERY = "pending_recovery_after_boot"
        const val KEY_BOOT_AT = "last_boot_at_ms"

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
