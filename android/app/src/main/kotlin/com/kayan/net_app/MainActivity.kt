package com.kayan.net_app

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
        if (BootReceiver.consumePendingRecovery(this)) {
            android.util.Log.i("NetMain", "pending recovery after boot — Flutter resume will run recovery pass")
        }

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
                        manager.sendTextMessage(to, null, body, null, null)
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
                "setAllowedPackages" -> {
                    val packages = call.argument<List<String>>("packages")?.toSet() ?: emptySet()
                    getSharedPreferences(NotificationListener.PREFS, MODE_PRIVATE)
                        .edit()
                        .putStringSet(NotificationListener.ALLOWED_PACKAGES, packages)
                        .apply()
                    result.success(true)
                }
                "peekPendingNotifications" -> {
                    val items = NotificationInboxStore(applicationContext).peek()
                    result.success(items.map { item ->
                        mapOf(
                            "id" to item.id,
                            "packageName" to item.packageName,
                            "title" to item.title,
                            "body" to item.body,
                            "timestampMillis" to item.timestampMillis,
                        )
                    })
                }
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
                "requestPostNotifications" -> {
                    val granted = requestPostNotificationsPermission()
                    result.success(granted)
                }
                "requestPhoneState" -> {
                    val granted = requestPhoneStatePermission()
                    result.success(granted)
                }
                "requestContacts" -> {
                    val granted = requestContactsPermission()
                    result.success(granted)
                }
                "hasContactsPermission" -> result.success(hasContactsPermission())
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
            sm?.activeSubscriptionInfoList != null
        } catch (_: Exception) {
            false
        }
    }

    private fun hasContactsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED

    private fun openOemAutostartSettings() {
        val intents = listOf(
            Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            Intent().setComponent(ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity")),
            Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
            Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")),
            Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
            Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")),
            Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")),
            Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")),
            Intent().setComponent(ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity")),
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) ?: continue
                startActivity(intent)
                return
            } catch (_: Exception) {
            }
        }
        throw Exception("No OEM autostart settings found")
    }

    override fun onSmsReceived(sender: String, body: String, timestampMillis: Long) {
        val payload = mapOf(
            "sender" to sender,
            "body" to body,
            "timestampMillis" to timestampMillis,
        )
        runOnUiThread { eventSink?.success(payload) }
    }

    override fun onDestroy() {
        if (SmsReceiver.listener === this) SmsReceiver.listener = null
        NotificationEventBus.sink = null
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

    private fun requestPostNotificationsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return true
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
        return false
    }

    private fun requestPhoneStatePermission(): Boolean {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_PHONE_STATE,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return true
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_PHONE_STATE),
            REQUEST_PHONE_STATE,
        )
        return false
    }

    private fun requestContactsPermission(): Boolean {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CONTACTS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return true
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CONTACTS),
            REQUEST_CONTACTS,
        )
        return false
    }

    companion object {
        private const val REQUEST_SMS = 1001
        private const val REQUEST_POST_NOTIFICATIONS = 1002
        private const val REQUEST_PHONE_STATE = 1003
        private const val REQUEST_CONTACTS = 1004
    }
}
