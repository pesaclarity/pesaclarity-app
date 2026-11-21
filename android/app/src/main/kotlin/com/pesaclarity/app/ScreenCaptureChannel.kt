package com.pesaclarity.app

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lets the person allow screenshots and screen recording (Profile, Security). MainActivity
 * sets FLAG_SECURE before any Dart code runs; "allow" clears it and "block" sets it again.
 */
class ScreenCaptureChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/screen_capture")

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "allow" -> setBlocked(false, result)
            "block" -> setBlocked(true, result)
            else -> result.notImplemented()
        }
    }

    private fun setBlocked(blocked: Boolean, result: MethodChannel.Result) {
        // As in MainActivity: debug builds are never blocked, so CI can capture UI screenshots.
        val debuggable = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        // A window's flags are changed on the UI thread.
        activity.runOnUiThread {
            activity.window.setFlags(
                if (blocked && !debuggable) WindowManager.LayoutParams.FLAG_SECURE else 0,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
            result.success(null)
        }
    }
}
