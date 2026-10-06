package com.kayan.net_app

import android.content.ComponentName

/** Pure parser for Settings.Secure.enabled_notification_listeners. */
internal object NotificationAccessChecker {
    fun isGranted(enabledListeners: String?, expected: ComponentName): Boolean {
        if (enabledListeners.isNullOrBlank()) return false
        return enabledListeners.split(":").any { raw ->
            ComponentName.unflattenFromString(raw) == expected
        }
    }
}
