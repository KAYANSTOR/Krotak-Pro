package com.kayan.net_app

import android.content.ComponentName
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationAccessCheckerTest {
    private val expected = ComponentName(
        "com.kayan.net_app",
        "com.kayan.net_app.NotificationListener",
    )

    @Test
    fun listenerIsGrantedWhenComponentIsInSecureSetting() {
        assertTrue(
            NotificationAccessChecker.isGranted(
                "other/.Listener:com.kayan.net_app/.NotificationListener",
                expected,
            ),
        )
    }

    @Test
    fun listenerIsDeniedWhenComponentIsMissingOrSettingIsEmpty() {
        assertFalse(NotificationAccessChecker.isGranted("other/.Listener", expected))
        assertFalse(NotificationAccessChecker.isGranted(null, expected))
    }
}
