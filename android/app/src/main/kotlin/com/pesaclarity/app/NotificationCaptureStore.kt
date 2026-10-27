package com.pesaclarity.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/**
 * The senders to watch, and messages read from notifications until the app
 * takes them. Each queued message is encrypted with a key that never leaves
 * the Android Keystore, in a file excluded from backups.
 */
object NotificationCaptureStore {
    private const val PREFS = "notification_capture"
    private const val SENDERS = "senders"
    private const val QUEUE_FILE = "notification-queue"
    private const val KEY_ALIAS = "pesaclarity.notification-queue"
    private const val RECENT_LIMIT = 500

    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())

    // Messaging notifications repeat earlier messages each time one arrives.
    private val recent = LinkedHashSet<String>()

    @Volatile
    var onArrival: (() -> Unit)? = null

    fun watched(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(SENDERS, emptySet())
            .orEmpty()

    fun setWatched(context: Context, senders: Collection<String>) {
        val normalised = senders.map(SmsChannel::normalise).filter { it.isNotEmpty() }.toSet()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putStringSet(SENDERS, normalised)
            .apply()
        if (normalised.isEmpty()) clear(context)
    }

    /** Queues [messages] not seen recently; true when any was new. */
    internal fun append(
        context: Context,
        messages: List<NotificationCaptureService.Message>,
    ): Boolean =
        synchronized(lock) {
            val fresh = messages.filter { recent.add(fingerprint(it)) }
            while (recent.size > RECENT_LIMIT) recent.remove(recent.first())
            if (fresh.isEmpty()) return false
            val key = key()
            queueFile(context).appendText(
                fresh.joinToString("") { encrypt(key, toJson(it)) + "\n" },
            )
            true
        }

    /** Every queued message, oldest first; the queue is emptied. */
    fun drain(context: Context): List<Map<String, Any>> =
        synchronized(lock) {
            val file = queueFile(context)
            if (!file.exists()) return emptyList()
            val lines = file.readLines()
            file.delete()
            val key = key()
            lines.mapNotNull { line ->
                runCatching {
                    val json = JSONObject(decrypt(key, line))
                    mapOf(
                        "sender" to json.getString("sender"),
                        "body" to json.getString("body"),
                        "receivedAtMillis" to json.getLong("receivedAtMillis"),
                    )
                }.getOrNull()
            }
        }

    fun announceArrival() {
        main.post { onArrival?.invoke() }
    }

    private fun clear(context: Context) =
        synchronized(lock) {
            queueFile(context).delete()
            recent.clear()
        }

    private fun queueFile(context: Context) = File(context.noBackupFilesDir, QUEUE_FILE)

    private fun fingerprint(message: NotificationCaptureService.Message): String {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(SmsChannel.normalise(message.sender).toByteArray())
        digest.update(0)
        digest.update(message.body.toByteArray())
        return Base64.encodeToString(digest.digest(), Base64.NO_WRAP)
    }

    private fun toJson(message: NotificationCaptureService.Message) =
        JSONObject()
            .put("sender", message.sender)
            .put("body", message.body)
            .put("receivedAtMillis", message.receivedAtMillis)
            .toString()

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun encrypt(key: SecretKey, text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val sealed = cipher.iv + cipher.doFinal(text.toByteArray())
        return Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    private fun decrypt(key: SecretKey, line: String): String {
        val sealed = Base64.decode(line, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, 12))
        return String(cipher.doFinal(sealed, 12, sealed.size - 12))
    }
}
