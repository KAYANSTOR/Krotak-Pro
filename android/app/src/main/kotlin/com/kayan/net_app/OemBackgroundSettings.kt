package com.kayan.net_app

import android.content.Intent

internal object OemBackgroundSettings {
    const val SAMSUNG_PACKAGE = "com.samsung.android.lool"
    const val SAMSUNG_ACTION =
        "com.samsung.android.sm.ACTION_OPEN_CHECKABLE_LISTACTIVITY"
    const val NEVER_SLEEPING_APPS_TYPE = 2

    fun samsungNeverSleepingIntent(): Intent =
        Intent(SAMSUNG_ACTION).apply {
            setPackage(SAMSUNG_PACKAGE)
            putExtra("activity_type", NEVER_SLEEPING_APPS_TYPE)
        }
}
