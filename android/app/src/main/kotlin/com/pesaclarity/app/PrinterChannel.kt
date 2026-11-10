package com.pesaclarity.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Prints on a small Bluetooth receipt printer at the counter: lists the printers paired with the
 * phone and sends ESC/POS bytes over the serial port profile most of them speak. Nothing leaves
 * the phone but the bytes sent to the printer the person chose.
 */
class PrinterChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "com.pesaclarity.app/printer")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingAccess: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supported" -> result.success(adapter() != null)
            "access" -> result.success(hasAccess())
            "requestAccess" -> requestAccess(result)
            "paired" -> paired(result)
            "print" -> print(call, result)
            "openSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun adapter() =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // Before Android 12 the install-time Bluetooth permission is enough.
    private fun hasAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestAccess(result: MethodChannel.Result) {
        if (hasAccess()) {
            result.success(true)
            return
        }
        if (pendingAccess != null) {
            result.error("busy", "A request is already open", null)
            return
        }
        pendingAccess = result
        activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), REQUEST_CODE)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_CODE) return
        val result = pendingAccess ?: return
        pendingAccess = null
        result.success(
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED,
        )
    }

    @SuppressLint("MissingPermission") // Checked by hasAccess.
    private fun paired(result: MethodChannel.Result) {
        val adapter = adapter()
        if (adapter == null || !hasAccess()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        result.success(
            adapter.bondedDevices.orEmpty().map {
                mapOf("name" to (it.name ?: it.address), "address" to it.address)
            },
        )
    }

    @SuppressLint("MissingPermission") // Checked by hasAccess.
    private fun print(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        val bytes = call.argument<ByteArray>("bytes")
        val adapter = adapter()
        if (address == null || bytes == null || adapter == null || !hasAccess()) {
            result.error("unavailable", "No printer to print on", null)
            return
        }
        io.execute {
            try {
                adapter.cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                device.createRfcommSocketToServiceRecord(SERIAL_PORT).use { socket ->
                    socket.connect()
                    socket.outputStream.write(bytes)
                    socket.outputStream.flush()
                    // Lets the printer take the last bytes before the link closes.
                    Thread.sleep(SETTLE_MS)
                }
                main.post { result.success(true) }
            } catch (e: Exception) {
                main.post { result.error("print_failed", e.message, null) }
            }
        }
    }

    companion object {
        const val REQUEST_CODE = 4702

        // The Bluetooth serial port profile.
        private val SERIAL_PORT: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val SETTLE_MS = 400L
    }
}
