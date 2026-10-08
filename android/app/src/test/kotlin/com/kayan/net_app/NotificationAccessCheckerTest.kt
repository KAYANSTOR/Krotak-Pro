package com.kayan.net_app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationAccessCheckerTest {
    private val expectedPackage = "com.kayan.net_app"
    private val expectedClassName = "com.kayan.net_app.NotificationListener"

    @Test
    fun listenerIsGrantedWhenComponentIsInSecureSetting() {
        assertTrue(
            NotificationAccessChecker.isGranted(
                "other/.Listener:com.kayan.net_app/.NotificationListener",
                expectedPackage,
                expectedClassName,
            ),
        )
    }

    @Test
    fun listenerIsDeniedWhenComponentIsMissingOrSettingIsEmpty() {
        assertFalse(
            NotificationAccessChecker.isGranted(
                "other/.Listener",
                expectedPackage,
                expectedClassName,
            ),
        )
        assertFalse(
            NotificationAccessChecker.isGranted(
                null,
                expectedPackage,
                expectedClassName,
            ),
        )
    }
}
