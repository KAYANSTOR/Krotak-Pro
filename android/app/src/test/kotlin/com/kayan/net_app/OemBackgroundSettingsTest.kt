package com.kayan.net_app

import org.junit.Assert.assertEquals
import org.junit.Test

class OemBackgroundSettingsTest {
    @Test
    fun samsungIntentTargetsNeverSleepingApps() {
        val intent = OemBackgroundSettings.samsungNeverSleepingIntent()
        assertEquals(OemBackgroundSettings.SAMSUNG_ACTION, intent.action)
        assertEquals(OemBackgroundSettings.SAMSUNG_PACKAGE, intent.`package`)
        assertEquals(
            OemBackgroundSettings.NEVER_SLEEPING_APPS_TYPE,
            intent.getIntExtra("activity_type", -1),
        )
    }
}
