package com.kayan.net_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.time.ZoneId

/**
 * Schedules a local-midnight check for the POS daily summary.
 *
 * Android may defer inexact alarms. The existing idempotency fence in
 * [com.kayan.net_app] Dart [sendDue] still prevents a second SMS.
 * This does not claim a silent send while the process is force-stopped.
 */
object DailySummaryScheduler {
    const val ACTION = "com.kayan.net_app.action.DAILY_POS_SUMMARY"
    const val PREFS = "net_daily_summary"
    const val KEY_ENABLED = "enabled"
    private const val TAG = "DailySummaryScheduler"
    private const val REQUEST_CODE = 4601

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun schedule(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, true)
            .apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val triggerAt = DailySummarySchedule.nextTriggerMillis(
            System.currentTimeMillis(),
            ZoneId.systemDefault(),
        )
        val pending = pendingIntent(context)
        alarm.cancel(pending)
        alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        Log.i(TAG, "scheduled daily summary check at=$triggerAt")
    }

    fun cancel(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, false)
            .apply()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarm.cancel(pendingIntent(context))
        Log.i(TAG, "cancelled daily summary check")
    }

    fun rescheduleIfEnabled(context: Context) {
        if (isEnabled(context)) schedule(context)
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DailySummaryReceiver::class.java).apply {
            action = ACTION
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }
}
