package com.pesaclarity.app

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Gives Dart a readable name for this phone, such as "Tecno Spark 20", for the device list, and
 * whether it is charging, so on-phone learning runs only then.
 */
object DeviceChannel {
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, "com.pesaclarity.app/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "name" -> result.success(name())
                "charging" -> result.success(charging(context))
                else -> result.notImplemented()
            }
        }
    }

    private fun charging(context: Context): Boolean {
        val battery = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        return battery?.isCharging ?: false
    }

    private fun name(): String {
        val maker = Build.MANUFACTURER.orEmpty().trim().replaceFirstChar { it.uppercase() }
        val model = Build.MODEL.orEmpty().trim()
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
    }
}
