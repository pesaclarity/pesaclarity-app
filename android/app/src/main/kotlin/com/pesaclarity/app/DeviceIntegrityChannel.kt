package com.pesaclarity.app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Light signs that the phone is rooted or the app was tampered with. Uses no
 * Google services, so it works the same in the play and foss builds. These
 * checks are easy to hide from; the app only warns and never blocks.
 */
class DeviceIntegrityChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/device_integrity")

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() = methods.setMethodCallHandler(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "check" ->
                result.success(
                    mapOf(
                        "suBinary" to hasSuBinary(),
                        "testKeys" to (Build.TAGS?.contains("test-keys") == true),
                        "appDebuggable" to
                            ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
                    ),
                )
            else -> result.notImplemented()
        }
    }

    private fun hasSuBinary() = SU_PATHS.any { runCatching { File(it).exists() }.getOrDefault(false) }

    private companion object {
        val SU_PATHS =
            listOf(
                "/system/bin/su",
                "/system/xbin/su",
                "/system/sbin/su",
                "/sbin/su",
                "/vendor/bin/su",
                "/su/bin/su",
                "/data/local/su",
                "/data/local/bin/su",
                "/data/local/xbin/su",
                "/system/app/Superuser.apk",
            )
    }
}
