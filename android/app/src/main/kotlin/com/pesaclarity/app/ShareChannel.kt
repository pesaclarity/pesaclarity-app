package com.pesaclarity.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the Android share sheet with prefilled text. The person picks the
 * app, such as WhatsApp, and sends it themselves; nothing is sent from here.
 */
class ShareChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/share")

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareText" -> {
                val text = call.argument<String>("text")
                if (text.isNullOrBlank()) {
                    result.error("argument", "text is required", null)
                    return
                }
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                try {
                    activity.startActivity(Intent.createChooser(send, null))
                    result.success(null)
                } catch (e: ActivityNotFoundException) {
                    result.error("unavailable", "No app can share text", null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
