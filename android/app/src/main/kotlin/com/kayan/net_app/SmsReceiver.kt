package com.kayan.net_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Receives SMS_RECEIVED broadcasts, persists them to [SmsInboxStore], and
 * optionally forwards to a live [SmsListener] (MainActivity) when present.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        // قد يكون النظام أنشأ عملية جديدة لهذا البثّ وحده. إبقاء عملية التسليم
        // حيّة يمنع ضياع القسيمة بعد البيع؛ الطلب مُقيَّد زمنياً في
        // DeliveryKeepAlivePolicy وآمن من الخلفية (يُبتلع الرفض).
        try {
            DeliveryKeepAliveService.requestStart(
                context,
                DeliveryKeepAliveService.smsPermissionsGranted(context),
            )
        } catch (e: Exception) {
            Log.w(TAG, "keep-alive start after sms failed: ${e.message}")
        }
        val store = SmsInboxStore(context)
        for (sms in messages) {
            val sender = sms.displayOriginatingAddress ?: continue
            val body = sms.messageBody ?: continue
            val timestamp = sms.timestampMillis

            Log.d(TAG, "SMS from=$sender len=${body.length}")
            store.append(sender, body, timestamp)
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
