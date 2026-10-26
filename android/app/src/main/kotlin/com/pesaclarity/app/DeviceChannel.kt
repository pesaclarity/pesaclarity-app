package com.pesaclarity.app

import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Gives Dart a readable name for this phone, such as "Tecno Spark 20", for the device list. */
object DeviceChannel {
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.pesaclarity.app/device").setMethodCallHandler { call, result ->
            if (call.method == "name") result.success(name()) else result.notImplemented()
        }
    }

    private fun name(): String {
        val maker = Build.MANUFACTURER.orEmpty().trim().replaceFirstChar { it.uppercase() }
        val model = Build.MODEL.orEmpty().trim()
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
    }
}
