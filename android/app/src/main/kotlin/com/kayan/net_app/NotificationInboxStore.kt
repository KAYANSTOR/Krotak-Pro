package com.kayan.net_app

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class PendingNotification(
    val id: String,
    val packageName: String,
    val title: String?,
    val body: String,
    val timestampMillis: Long,
)

internal class NotificationInboxStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val lock = Any()

    fun append(packageName: String, title: String?, body: String, timestampMillis: Long): PendingNotification {
        val item = PendingNotification(UUID.randomUUID().toString(), packageName, title, body, timestampMillis)
        synchronized(lock) {
            val items = read().toMutableList()
            items.add(item)
            while (items.size > MAX_ITEMS) items.removeAt(0)
            write(items)
        }
        return item
    }

    fun peek(limit: Int = MAX_ITEMS): List<PendingNotification> = synchronized(lock) { read().take(limit) }

    fun ack(ids: Set<String>) {
        if (ids.isEmpty()) return
        synchronized(lock) { write(read().filterNot { ids.contains(it.id) }) }
    }

    private fun read(): List<PendingNotification> {
        val encrypted = prefs.getString(KEY_QUEUE, null) ?: return emptyList()
        return try {
            val plain = decrypt(encrypted)
            val array = JSONArray(plain)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val o = array.getJSONObject(i)
                    add(PendingNotification(o.getString("id"), o.getString("packageName"), o.optString("title").ifBlank { null }, o.getString("body"), o.getLong("timestampMillis")))
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun write(items: List<PendingNotification>) {
        val array = JSONArray()
        items.forEach { item ->
            array.put(JSONObject().apply {
                put("id", item.id)
                put("packageName", item.packageName)
                put("title", item.title ?: "")
                put("body", item.body)
                put("timestampMillis", item.timestampMillis)
            })
        }
        prefs.edit().putString(KEY_QUEUE, encrypt(array.toString())).apply()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(KEY_ALIAS, null)
        if (existing is SecretKey) return existing
        val generator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
        generator.init(256)
        return generator.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        val bytes = Base64.encodeToString(cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8)), Base64.NO_WRAP)
        return "$iv:$bytes"
    }

    private fun decrypt(value: String): String {
        val parts = value.split(':', limit = 2)
        require(parts.size == 2)
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val cipherText = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(cipherText), StandardCharsets.UTF_8)
    }

    companion object {
        private const val PREFS = "net_notification_inbox"
        private const val KEY_QUEUE = "encrypted_queue"
        private const val KEY_ALIAS = "net_notification_inbox_key"
        private const val MAX_ITEMS = 200
    }
}
