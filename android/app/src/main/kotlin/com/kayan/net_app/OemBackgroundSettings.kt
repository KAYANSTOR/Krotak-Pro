package com.kayan.net_app

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.provider.Settings

internal object OemBackgroundSettings {
    data class IntentContract(
        val action: String,
        val targetPackage: String? = null,
        val integerExtras: Map<String, Int> = emptyMap(),
    )

    const val SAMSUNG_PACKAGE = "com.samsung.android.lool"
    const val SAMSUNG_ACTION =
        "com.samsung.android.sm.ACTION_OPEN_CHECKABLE_LISTACTIVITY"
    const val NEVER_SLEEPING_APPS_TYPE = 2
    const val BATTERY_SETTINGS_ACTION = "android.settings.BATTERY_SETTINGS"

    fun samsungNeverSleepingIntentContract() = IntentContract(
        action = SAMSUNG_ACTION,
        targetPackage = SAMSUNG_PACKAGE,
        integerExtras = mapOf("activity_type" to NEVER_SLEEPING_APPS_TYPE),
    )

    fun samsungNeverSleepingIntent(): Intent = samsungNeverSleepingIntentContract().let { contract ->
        Intent(contract.action).apply {
            contract.targetPackage?.let { setPackage(it) }
            contract.integerExtras.forEach { (key, value) -> putExtra(key, value) }
        }
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

    fun batterySettingsIntentContract() = IntentContract(action = BATTERY_SETTINGS_ACTION)

    fun batterySettingsIntent(): Intent = Intent(batterySettingsIntentContract().action)
}
