package com.kayan.net_app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * WP-9 — تصنيف أسباب إنهاء العملية (الدليل قبل الإصلاح).
 *
 * الأرقام منسوخة من `ActivityManager.REASON_*` كثوابت وقت التصنيف، فيبقى هذا
 * الملف منطقًا خالصًا يُختبر على JVM (انظر ProcessExitReasonCodesTest).
 *
 * الأسماء العربية للعرض تُبنى في طبقة Dart (الاختبار هناك)،
 * ويُرسل من هنا رمز مستقر فقط بلا أي نص لاتيني للواجهة.
 */
internal object ProcessExitReasonCodes {
    private val BY_REASON = mapOf(
        0 to "unknown",
        1 to "exit_self",
        2 to "signaled",
        3 to "low_memory",
        4 to "crash",
        5 to "crash_native",
        6 to "anr",
        7 to "initialization_failure",
        8 to "permission_change",
        9 to "excessive_resource_usage",
        10 to "user_requested",
        11 to "user_stopped",
        12 to "dependency_died",
        13 to "other",
        14 to "freezer",
        15 to "package_state_change",
        16 to "package_updated",
    )

    fun codeOf(reason: Int): String = BY_REASON[reason] ?: "unknown"
}

/**
 * قراءة أسباب الإنهاء التاريخية من النظام (Android 11+).
 *
 * مقصود بالتشخيص فقط: لا نمنع قتل العملية ولا ندّعي منع Force-stop.
 * الفشل يُبتلع ويُرجع تاريخ فارغ، فلا تُسقط الشاشة.
 */
internal object ProcessExitReasonsReader {
    private const val TAG = "NetProcessExitReasons"

    fun read(context: Context, limit: Int = 8): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return emptyList()
            val safeLimit = if (limit <= 0) 8 else limit
            manager.getHistoricalProcessExitReasons(context.packageName, 0, safeLimit).map { info ->
                mapOf(
                    "code" to ProcessExitReasonCodes.codeOf(info.reason),
                    "reason" to info.reason,
                    "timestampMillis" to info.timestamp,
                    "importance" to info.importance,
                    "description" to (info.description ?: ""),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "read failed: ${e.message}")
            emptyList()
        }
    }
}
