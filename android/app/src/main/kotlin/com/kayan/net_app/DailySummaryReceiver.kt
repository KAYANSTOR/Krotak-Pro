package com.kayan.net_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Midnight tick for the POS daily summary.
 * Reschedules the next night, marks recovery pending, and tries the same
 * auto-start path already used after boot. OEMs may block the activity start;
 * the next app open still runs sendDue exactly once.
 */
class DailySummaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != DailySummaryScheduler.ACTION) return
        Log.i(TAG, "daily summary alarm")
        DailySummaryScheduler.rescheduleIfEnabled(context)
        try {
            context.getSharedPreferences(BootReceiver.PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(BootReceiver.KEY_PENDING_RECOVERY, true)
                .putLong(BootReceiver.KEY_BOOT_AT, System.currentTimeMillis())
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "could not mark recovery: ${e.message}")
        }
        try {
            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra(BootReceiver.EXTRA_FROM_BOOT, true)
                putExtra(EXTRA_DAILY_SUMMARY, true)
            }
            context.startActivity(launch)
        } catch (e: Exception) {
            Log.w(TAG, "auto-start blocked: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "DailySummaryReceiver"
        const val EXTRA_DAILY_SUMMARY = "net_daily_summary"
    }
}
