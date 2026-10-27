package com.pesaclarity.app

import android.app.Activity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The foss build signs in by email only and carries no Google libraries. */
class GoogleSignInChannel(
    @Suppress("UNUSED_PARAMETER") activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/google_sign_in")

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(false)
            "requestIdToken" -> result.error("unavailable", "Not in this build", null)
            else -> result.notImplemented()
        }
    }
}
