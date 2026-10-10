package com.kayan.net_app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * WP-9 / H1 — إعادة تشغيل مؤجلة لخدمة الحفاظ بعد `onTimeout`.
 *
 * لماذا مجدول وليس بداية فورية: النظام على Android 12+ يرفض بدء خدمة
 * أمامية من الخلفية بلا استثناء، فنطلب المحاولة عبر عمل مجدول متأخر
 * (JobScheduler المدمج في النظام — بلا تبعية Gradle جديدة، ونفس دور WorkManager)،
 * والمحاولة نفسها محمية بـtry/catch ومُسجّلة في سجل الأحداث.
 * إن رفضها النظام فالمسار المعتمد المتبقي هو: فتح التطبيق أو وصول SMS
 * (ينادي [DeliveryKeepAliveService.requestStart] من سياق مسموح)، وهو موثّق في تقرير WP-9.
 */
internal object KeepAliveRestartScheduler {
    private const val TAG = "NetKeepAliveRestart"
    private const val JOB_ID = 7102

    fun schedule(
        context: Context,
        delayMillis: Long = DeliveryKeepAlivePolicy.TIMEOUT_RESTART_DELAY_MILLIS,
    ) {
        try {
            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            if (scheduler == null) {
                DeliveryKeepAliveEventStore.record(
                    context,
                    DeliveryKeepAliveEvent.RESTART_SCHEDULED,
                    "unsupported",
                )
                return
            }
            val component = ComponentName(context, KeepAliveRestartJobService::class.java)
            val safeDelay = if (delayMillis < 0) 0L else delayMillis
            val job = JobInfo.Builder(JOB_ID, component)
                .setMinimumLatency(safeDelay)
                .setOverrideDeadline(safeDelay * 2)
                .setPersisted(true)
                .build()
            scheduler.schedule(job)
            DeliveryKeepAliveEventStore.record(
                context,
                DeliveryKeepAliveEvent.RESTART_SCHEDULED,
                "delay=${safeDelay / 1000}s",
            )
        } catch (e: Exception) {
            Log.w(TAG, "schedule failed: ${e.message}")
            DeliveryKeepAliveEventStore.record(
                context,
                DeliveryKeepAliveEvent.RESTART_SCHEDULED,
                "failed",
            )
        }
    }
}

/**
 * عمل مجدول يحاول إعادة تشغيل الخدمة مرة واحدة وينتهي فورًا.
 * لا يُعيد الجدولة داخله (بلا حلقة لا تنتهي)، وأي رفض يُسجّل ويُبتلع.
 */
class KeepAliveRestartJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        DeliveryKeepAliveEventStore.record(this, DeliveryKeepAliveEvent.RESTART_ATTEMPTED, "job")
        try {
            DeliveryKeepAliveService.requestStart(
                applicationContext,
                DeliveryKeepAliveService.smsPermissionsGranted(applicationContext),
            )
        } catch (e: Exception) {
            Log.w(TAG, "restart attempt failed: ${e.message}")
        }
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false

    private companion object {
        private const val TAG = "NetKeepAliveRestartJob"
    }
}
