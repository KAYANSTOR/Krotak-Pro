package com.kayan.net_app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings

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

    /** مسارات بديلة لشاشات Samsung Device Care / البطارية. */
    fun samsungBackgroundIntents(packageName: String): List<Intent> = listOf(
        samsungNeverSleepingIntent(),
        Intent().setComponent(
            ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.battery.ui.BatteryActivity",
            ),
        ),
        Intent().setComponent(
            ComponentName(
                "com.samsung.android.sm",
                "com.samsung.android.sm.ui.battery.BatteryActivity",
            ),
        ),
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
        },
        Intent(BATTERY_SETTINGS_ACTION),
    )

    fun batterySettingsIntent(): Intent = Intent(BATTERY_SETTINGS_ACTION)
}
