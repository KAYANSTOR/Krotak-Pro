package com.kayan.net_app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts two channels:
 * - MethodChannel `com.kayan.net/sms` for sendSms / requestPermissions / hasPermissions
 * - EventChannel `com.kayan.net/sms_stream` for live incoming SMS events
 */
class MainActivity : FlutterActivity(), SmsListener {
    private val methodChannelName = "com.kayan.net/sms"
    private val eventChannelName = "com.kayan.net/sms_stream"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
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
                            val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                applicationContext.getSystemService(SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsManager.getDefault()
                            }
                            smsManager?.sendTextMessage(to, null, body, null, null)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("send_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    SmsReceiver.listener = this@MainActivity
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    if (SmsReceiver.listener === this@MainActivity) {
                        SmsReceiver.listener = null
                    }
                }
            })
    }

    override fun onSmsReceived(sender: String, body: String, timestampMillis: Long) {
        runOnUiThread {
            eventSink?.success(
                mapOf(
                    "sender" to sender,
                    "body" to body,
                    "timestampMillis" to timestampMillis,
                )
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SmsReceiver.listener = this
    }

    override fun onDestroy() {
        if (SmsReceiver.listener === this) {
            SmsReceiver.listener = null
        }
        super.onDestroy()
    }

    private fun hasSmsPermissions(): Boolean {
        val receive = ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS)
        val read = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS)
        val send = ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
        return receive == PackageManager.PERMISSION_GRANTED &&
            read == PackageManager.PERMISSION_GRANTED &&
            send == PackageManager.PERMISSION_GRANTED
    }

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
