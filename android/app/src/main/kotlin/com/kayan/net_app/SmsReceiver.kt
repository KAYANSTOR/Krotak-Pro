package com.kayan.net_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        for (sms in messages) {
            val sender = sms.displayOriginatingAddress ?: continue
            val body = sms.messageBody ?: continue
            val timestamp = sms.timestampMillis

            Log.d(TAG, "SMS from=$sender len=${body.length}")
            listener?.onSmsReceived(sender, body, timestamp)
        }
    }

    companion object {
        private const val TAG = "NetSmsReceiver"

        @Volatile
        var listener: SmsListener? = null
    }
}

interface SmsListener {
    fun onSmsReceived(sender: String, body: String, timestampMillis: Long)
}
