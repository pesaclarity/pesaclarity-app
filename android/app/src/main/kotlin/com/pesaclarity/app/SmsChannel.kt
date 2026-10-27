package com.pesaclarity.app

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * SMS access for the Dart side, limited to the sender IDs it passes in.
 * Messages from any other sender are filtered out in the inbox query and
 * the receiver, so they never reach Dart.
 */
class SmsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/sms")
    private val events = EventChannel(messenger, "com.pesaclarity.app/sms/incoming")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingAccess: MethodChannel.Result? = null
    private var receiver: BroadcastReceiver? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        stopReceiver()
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(if (hasPermissions()) GRANTED else DENIED)
            "requestAccess" -> requestAccess(result)
            "openSettings" -> {
                openSettings()
                result.success(null)
            }
            "readInbox" -> {
                if (!hasPermissions()) {
                    result.error("permission", "SMS permission is not granted", null)
                    return
                }
                val senders = call.argument<List<String>>("senders").orEmpty()
                val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                io.execute {
                    try {
                        val messages = readInbox(senders, since)
                        main.post { result.success(messages) }
                    } catch (e: Exception) {
                        main.post { result.error("read_failed", e.message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermissions() = PERMISSIONS.all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(GRANTED)
            return
        }
        if (pendingAccess != null) {
            result.error("busy", "A permission request is already showing", null)
            return
        }
        pendingAccess = result
        activity.requestPermissions(PERMISSIONS, REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val result = pendingAccess ?: return
        pendingAccess = null
        val granted =
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        result.success(
            when {
                granted -> GRANTED
                // After a refusal Android stops showing the dialog; only Settings can grant it.
                !activity.shouldShowRequestPermissionRationale(Manifest.permission.READ_SMS) -> BLOCKED
                else -> DENIED
            },
        )
    }

    private fun openSettings() {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", activity.packageName, null)),
        )
    }

    private fun readInbox(senders: List<String>, sinceMillis: Long): List<Map<String, Any>> {
        val watched = senders.map(::normalise).filter { it.isNotEmpty() }.distinct()
        if (watched.isEmpty()) return emptyList()
        val selection =
            "UPPER(TRIM(${Telephony.Sms.ADDRESS})) IN (${watched.joinToString(",") { "?" }})" +
                " AND ${Telephony.Sms.DATE} >= ?"
        val args = (watched + sinceMillis.toString()).toTypedArray()
        val projection =
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE, Telephony.Sms.DATE_SENT)
        val messages = mutableListOf<Map<String, Any>>()
        activity.contentResolver
            .query(Telephony.Sms.Inbox.CONTENT_URI, projection, selection, args, "${Telephony.Sms.DATE} ASC")
            ?.use { cursor ->
                val address = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
                val body = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
                val date = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)
                val dateSent = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE_SENT)
                while (cursor.moveToNext()) {
                    val sent = cursor.getLong(dateSent)
                    messages +=
                        message(
                            cursor.getString(address) ?: continue,
                            cursor.getString(body) ?: continue,
                            if (sent > 0) sent else cursor.getLong(date),
                        )
                }
            }
        return messages
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        stopReceiver()
        val watched = (arguments as? List<*>).orEmpty().filterIsInstance<String>().map(::normalise).toSet()
        val smsReceiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
                    val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
                    // A long message arrives in parts; join them as the inbox does.
                    parts
                        .filterNotNull()
                        .groupBy { it.originatingAddress.orEmpty() }
                        .filterKeys { normalise(it) in watched }
                        .forEach { (address, group) ->
                            val body = group.joinToString("") { it.messageBody.orEmpty() }
                            sink.success(message(address, body, group.first().timestampMillis))
                        }
                }
            }
        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        // Requiring BROADCAST_SMS means only the telephony stack can deliver, not other apps.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(
                smsReceiver,
                filter,
                Manifest.permission.BROADCAST_SMS,
                null,
                Context.RECEIVER_EXPORTED,
            )
        } else {
            activity.registerReceiver(smsReceiver, filter, Manifest.permission.BROADCAST_SMS, null)
        }
        receiver = smsReceiver
    }

    override fun onCancel(arguments: Any?) = stopReceiver()

    private fun stopReceiver() {
        receiver?.let { activity.unregisterReceiver(it) }
        receiver = null
    }

    private fun message(sender: String, body: String, receivedAtMillis: Long) =
        mapOf("sender" to sender, "body" to body, "receivedAtMillis" to receivedAtMillis)

    companion object {
        private const val REQUEST_CODE = 4701
        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val BLOCKED = "blocked"
        private val PERMISSIONS = arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS)

        // Matches ujumbe's SenderFilter: case-insensitive, ignoring surrounding spaces.
        fun normalise(sender: String) = sender.trim().uppercase()
    }
}
