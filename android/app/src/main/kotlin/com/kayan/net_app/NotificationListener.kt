package com.kayan.net_app

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

internal object NotificationEventBus {
    @Volatile var sink: ((Map<String, Any?>) -> Unit)? = null
}

class NotificationListener : NotificationListenerService() {
    private val store by lazy { NotificationInboxStore(applicationContext) }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!isAllowedPackage(sbn.packageName)) return
        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val body = extractBody(extras)
        if (title.isEmpty() && body.isEmpty()) return

        val item = store.append(sbn.packageName, title.ifEmpty { null }, body, sbn.postTime)
        NotificationEventBus.sink?.invoke(
            mapOf(
                "id" to item.id,
                "packageName" to item.packageName,
                "title" to item.title,
                "body" to item.body,
                "timestampMillis" to item.timestampMillis,
            ),
        )
    }

    private fun isAllowedPackage(packageName: String): Boolean {
        val packages = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(ALLOWED_PACKAGES, emptySet()) ?: emptySet()
        return packages.contains(packageName)
    }

    private fun extractBody(extras: android.os.Bundle): String {
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (text.isNotEmpty()) return text
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        if (big.isNotEmpty()) return big
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
        return lines?.joinToString("\n") { it.toString().trim() }?.trim().orEmpty()
    }

    companion object {
        const val PREFS = "net_notification_listener"
        const val ALLOWED_PACKAGES = "allowed_packages"

        fun component(context: Context) = ComponentName(context, NotificationListener::class.java)
    }
}
