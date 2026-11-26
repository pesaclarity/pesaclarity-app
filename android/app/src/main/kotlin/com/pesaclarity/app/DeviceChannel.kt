package com.pesaclarity.app

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Gives Dart a readable name for this phone, such as "Tecno Spark 20", for the device list,
 * whether it is charging, so on-phone learning runs only then, and Android's major version,
 * such as "13", for a crash report (never the build fingerprint). For Ask's money model: the
 * phone's memory, free space and whether the network is unmetered (Wi-Fi).
 */
object DeviceChannel {
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, "com.pesaclarity.app/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "name" -> result.success(name())
                "charging" -> result.success(charging(context))
                "systemVersion" -> result.success(Build.VERSION.RELEASE.orEmpty().takeWhile { it.isDigit() })
                "memory" -> result.success(memory(context))
                "freeSpace" -> result.success(
                    runCatching { StatFs(call.arguments as String).availableBytes }.getOrNull()
                )
                "unmetered" -> result.success(unmetered(context))
                // Auto backup already leaves every app file out (backup_rules.xml).
                "excludeFromBackup" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    private fun charging(context: Context): Boolean {
        val battery = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        return battery?.isCharging ?: false
    }

    private fun memory(context: Context): Long? {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return null
        val info = ActivityManager.MemoryInfo()
        manager.getMemoryInfo(info)
        return info.totalMem
    }

    private fun unmetered(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val caps = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    private fun name(): String {
        val maker = Build.MANUFACTURER.orEmpty().trim().replaceFirstChar { it.uppercase() }
        val model = Build.MODEL.orEmpty().trim()
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
    }
}
