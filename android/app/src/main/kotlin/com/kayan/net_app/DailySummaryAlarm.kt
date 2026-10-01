package com.kayan.net_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Calendar

/**
 * Local-midnight kick for the POS daily summary.
 *
 * The financial send still lives in Dart (`sendDue`) and stays idempotent.
 * This alarm only asks the process to run recovery. OEM force-stop can still
 * block the launch; the recovery cycle remains the fallback.
 */
object DailySummaryAlarm {
    private const val TAG = "DailySummaryAlarm"
    const val ACTION = "com.kayan.net_app.DAILY_SUMMARY"
    private const val PREFS = "net_daily_summary"
    private const val KEY_ENABLED = "enabled"
    private const val REQUEST_CODE = 4401

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_ENABLED, enabled)
            .apply()
        if (enabled) schedule(context) else cancel(context)
    }

    fun scheduleIfEnabled(context: Context) {
        val enabled = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)
        if (enabled) schedule(context)
    }

    fun schedule(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = pendingIntent(context)
        val triggerAt = nextFireAtMillis()
        try {
            val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                alarmManager.canScheduleExactAlarms()
            if (canExact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pending,
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    pending,
                )
            }
            Log.i(TAG, "scheduled daily summary at $triggerAt exact=$canExact")
        } catch (e: SecurityException) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            Log.w(TAG, "exact alarm denied, used inexact: ${e.message}")
        }
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(pendingIntent(context))
    }

    fun nextFireAtMillis(now: Long = System.currentTimeMillis()): Long {
        val calendar = Calendar.getInstance().apply {
            timeInMillis = now
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 5)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now) add(Calendar.DAY_OF_YEAR, 1)
        }
        return calendar.timeInMillis
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DailySummaryReceiver::class.java).apply {
            action = ACTION
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

class DailySummaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != DailySummaryAlarm.ACTION) return
        Log.i(TAG, "daily summary alarm fired")
        DailySummaryAlarm.schedule(context)
        try {
            context.getSharedPreferences(BootReceiver.PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(BootReceiver.KEY_PENDING_RECOVERY, true)
                .apply()
        } catch (e: Exception) {
            Log.w(TAG, "failed to mark recovery: ${e.message}")
        }
        try {
            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra(EXTRA_FROM_ALARM, true)
            }
            context.startActivity(launch)
        } catch (e: Exception) {
            Log.w(TAG, "launch blocked: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "DailySummaryReceiver"
        const val EXTRA_FROM_ALARM = "net_daily_summary_alarm"
    }
}
