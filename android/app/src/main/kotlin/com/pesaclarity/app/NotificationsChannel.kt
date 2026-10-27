package com.pesaclarity.app

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Notification reading for the Dart side: whether the person allowed it, the
 * senders to watch, and the messages read so far. The arrivals stream only
 * says that something new is waiting; Dart then drains it.
 */
class NotificationsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/notifications")
    private val events = EventChannel(messenger, "com.pesaclarity.app/notifications/arrivals")
    private val io = Executors.newSingleThreadExecutor()
    private val component = ComponentName(activity, NotificationCaptureService::class.java)

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        NotificationCaptureStore.onArrival = null
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(if (allowed()) "granted" else "denied")
            "openSettings" -> {
                openSettings()
                result.success(null)
            }
            "setWatched" -> {
                val senders = call.argument<List<String>>("senders").orEmpty()
                io.execute {
                    NotificationCaptureStore.setWatched(activity, senders)
                    activity.runOnUiThread { result.success(null) }
                }
            }
            "drain" ->
                io.execute {
                    try {
                        val messages = NotificationCaptureStore.drain(activity)
                        activity.runOnUiThread { result.success(messages) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("drain_failed", e.message, null) }
                    }
                }
            else -> result.notImplemented()
        }
    }

    private fun allowed(): Boolean {
        val enabled = Settings.Secure.getString(activity.contentResolver, "enabled_notification_listeners")
        return enabled.orEmpty().split(':').any { ComponentName.unflattenFromString(it) == component }
    }

    private fun openSettings() {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
            } else {
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            }
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        NotificationCaptureStore.onArrival = { sink.success(null) }
    }

    override fun onCancel(arguments: Any?) {
        NotificationCaptureStore.onArrival = null
    }
}
