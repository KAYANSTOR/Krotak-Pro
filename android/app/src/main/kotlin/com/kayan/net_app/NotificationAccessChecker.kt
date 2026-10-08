package com.kayan.net_app

/** Pure parser for Settings.Secure.enabled_notification_listeners. */
internal object NotificationAccessChecker {
    fun isGranted(
        enabledListeners: String?,
        expectedPackage: String,
        expectedClassName: String,
    ): Boolean {
        if (enabledListeners.isNullOrBlank()) return false
        if (expectedPackage.isBlank() || expectedClassName.isBlank()) return false
        return enabledListeners.split(":").any { raw ->
            val separator = raw.indexOf('/')
            if (separator <= 0 || separator == raw.lastIndex) return@any false

            val packageName = raw.substring(0, separator)
            val rawClassName = raw.substring(separator + 1)
            val className = if (rawClassName.startsWith('.')) {
                packageName + rawClassName
            } else {
                rawClassName
            }
            packageName == expectedPackage && className == expectedClassName
        }
    }
}
