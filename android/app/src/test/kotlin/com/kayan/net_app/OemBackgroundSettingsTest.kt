package com.kayan.net_app

import org.junit.Assert.assertEquals
import org.junit.Test

class OemBackgroundSettingsTest {
    @Test
    fun samsungIntentTargetsNeverSleepingApps() {
        val contract = OemBackgroundSettings.samsungNeverSleepingIntentContract()
        assertEquals(OemBackgroundSettings.SAMSUNG_ACTION, contract.action)
        assertEquals(OemBackgroundSettings.SAMSUNG_PACKAGE, contract.targetPackage)
        assertEquals(
            OemBackgroundSettings.NEVER_SLEEPING_APPS_TYPE,
            contract.integerExtras["activity_type"],
        )
    }

    @Test
    fun batterySettingsIntentIsSafeFallback() {
        assertEquals(
            OemBackgroundSettings.BATTERY_SETTINGS_ACTION,
            OemBackgroundSettings.batterySettingsIntentContract().action,
        )
    }
}
