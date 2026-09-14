package com.kayan.net_app

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), SmsListener {
    private val methodChannelName = "com.kayan.net/sms"
    private val eventChannelName = "com.kayan.net/sms_stream"
    private val notificationMethodChannelName = "com.kayan.net/notifications"
    private val notificationEventChannelName = "com.kayan.net/notifications_stream"
    private val diagnosticsChannelName = "com.kayan.net/diagnostics"
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    requestSmsPermissions()
                    result.success(hasSmsPermissions())
                }
                "hasPermissions" -> result.success(hasSmsPermissions())
                "sendSms" -> {
                    val to = call.argument<String>("to")
                    val body = call.argument<String>("body")
                    if (to.isNullOrBlank() || body.isNullOrBlank()) {
                        result.error("invalid_args", "to and body are required", null)
                        return@setMethodCallHandler
                    }
                    if (!hasSmsPermissions()) {
                        result.error("no_permission", "SMS permission not granted", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            getSystemService(SmsManager::class.java)
                        } else {
                            @Suppress("DEPRECATION") SmsManager.getDefault()
                        }
                        manager?.sendTextMessage(to, null, body, null, null)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("send_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    SmsReceiver.listener = this@MainActivity
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    if (SmsReceiver.listener === this@MainActivity) SmsReceiver.listener = null
                }
            },
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationMethodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessGranted" -> result.success(isNotificationAccessGranted())
                "openAccessSettings" -> try {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("settings_failed", e.message, null)
                }
                "setAllowedPackages" -> {
                    val packages = call.argument<List<String>>("packages")?.toSet() ?: emptySet()
                    getSharedPreferences(NotificationListener.PREFS, MODE_PRIVATE)
                        .edit()
                        .putStringSet(NotificationListener.ALLOWED_PACKAGES, packages)
                        .apply()
                    result.success(true)
                }
                "peekPendingNotifications" ->
                    result.success(NotificationInboxStore(applicationContext).peek().map { it.toMap() })
                "ackPendingNotifications" -> {
                    val ids = call.argument<List<String>>("ids")?.toSet() ?: emptySet()
                    NotificationInboxStore(applicationContext).ack(ids)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, notificationEventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationEventBus.sink = { payload -> runOnUiThread { events?.success(payload) } }
                }

                override fun onCancel(arguments: Any?) {
                    NotificationEventBus.sink = null
                }
            },
        )

        // ── System diagnostics (1.0.9) ───────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagnosticsChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(probeCapabilities())
                "requestSmsPermissions" -> {
                    requestSmsPermissions()
                    result.success(hasSmsPermissions())
                }
                "openNotificationAccess" -> try {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("settings_failed", e.message, null)
                }
                "openBatteryOptimization" -> try {
                    openBatteryOptimizationSettings()
                    result.success(true)
                } catch (e: Exception) {
                    result.error("settings_failed", e.message, null)
                }
                "openAppSettings" -> try {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("settings_failed", e.message, null)
                }
                "openAutoStartSettings" -> try {
                    openOemAutostartSettings()
                    result.success(true)
                } catch (e: Exception) {
                    // Fallback to app settings
                    try {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            },
                        )
                        result.success(true)
                    } catch (e2: Exception) {
                        result.error("settings_failed", e2.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun probeCapabilities(): Map<String, Any?> {
        return mapOf(
            "smsPermissions" to hasSmsPermissions(),
            "notificationAccess" to isNotificationAccessGranted(),
            "batteryOptimizationIgnored" to isIgnoringBatteryOptimizations(),
            "dualSimReadable" to canReadSubscriptions(),
            "contactsPermission" to hasContactsPermission(),
            "foregroundOk" to true,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } catch (_: Exception) {
            false
        }
    }

    private fun openBatteryOptimizationSettings() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun canReadSubscriptions(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP_MR1) return false
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
                != PackageManager.PERMISSION_GRANTED
            ) {
                return false
            }
            val sm = getSystemService(TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            val list = sm?.activeSubscriptionInfoList
            list != null
        } catch (_: Exception) {
            false
        }
    }

    private fun hasContactsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    /** Best-effort OEM auto-start screens (Xiaomi / Huawei / Oppo / Samsung). */
    private fun openOemAutostartSettings() {
        val candidates = listOf(
            Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                ),
            ),
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                ),
            ),
            Intent().setComponent(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                ),
            ),
            Intent().setComponent(
                ComponentName(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity",
                ),
            ),
        )
        for (intent in candidates) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (_: Exception) {
                // try next OEM
            }
        }
        throw IllegalStateException("No OEM autostart activity found")
    }

    private fun PendingNotification.toMap(): Map<String, Any?> =
        mapOf(
            "id" to id,
            "packageName" to packageName,
            "title" to title,
            "body" to body,
            "timestampMillis" to timestampMillis,
        )

    override fun onSmsReceived(sender: String, body: String, timestampMillis: Long) {
        runOnUiThread {
            eventSink?.success(
                mapOf(
                    "sender" to sender,
                    "body" to body,
                    "timestampMillis" to timestampMillis,
                ),
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SmsReceiver.listener = this
    }

    override fun onDestroy() {
        if (SmsReceiver.listener === this) SmsReceiver.listener = null
        if (NotificationEventBus.sink != null) NotificationEventBus.sink = null
        super.onDestroy()
    }

    private fun isNotificationAccessGranted(): Boolean {
        val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it) == NotificationListener.component(this)
        }
    }

    private fun hasSmsPermissions(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsPermissions() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.RECEIVE_SMS,
                Manifest.permission.READ_SMS,
                Manifest.permission.SEND_SMS,
            ),
            REQUEST_SMS,
        )
    }

    companion object {
        private const val REQUEST_SMS = 1001
    }
}
