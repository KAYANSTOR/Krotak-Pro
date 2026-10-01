package com.kayan.net_app

import android.content.Intent

internal object OemBackgroundSettings {
    const val SAMSUNG_PACKAGE = "com.samsung.android.lool"
    const val SAMSUNG_ACTION =
        "com.samsung.android.sm.ACTION_OPEN_CHECKABLE_LISTACTIVITY"
    const val NEVER_SLEEPING_APPS_TYPE = 2
    const val BATTERY_SETTINGS_ACTION = "android.settings.BATTERY_SETTINGS"

    fun samsungNeverSleepingIntent(): Intent =
        Intent(SAMSUNG_ACTION).apply {
            setPackage(SAMSUNG_PACKAGE)
            putExtra("activity_type", NEVER_SLEEPING_APPS_TYPE)
        }

    fun batterySettingsIntent(): Intent = Intent(BATTERY_SETTINGS_ACTION)
}
