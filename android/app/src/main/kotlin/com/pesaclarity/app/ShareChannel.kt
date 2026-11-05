package com.pesaclarity.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.ContactsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the Android share sheet with prefilled text. The person picks the
 * app, such as WhatsApp, and sends it themselves; nothing is sent from here.
 *
 * Also opens the phone's own contact picker for one phone number. The
 * picker grants access to the one contact chosen, so no contacts
 * permission is needed and the contact list is never read.
 *
 * And opens the phone's own camera app for one photo, such as a paper
 * receipt. The camera app writes it to the app's cache through a
 * FileProvider, so no camera permission is needed.
 */
class ShareChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/share")
    private var pendingPick: MethodChannel.Result? = null
    private var pendingPhoto: Pair<MethodChannel.Result, File>? = null

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
            "pickPhone" -> {
                pendingPick?.success(null)
                pendingPick = result
                val pick = Intent(
                    Intent.ACTION_PICK,
                    ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                )
                try {
                    activity.startActivityForResult(pick, PICK_PHONE)
                } catch (e: ActivityNotFoundException) {
                    pendingPick = null
                    result.error("unavailable", "No contact picker", null)
                }
            }
            "takePhoto" -> {
                pendingPhoto?.first?.success(null)
                val dir = File(activity.cacheDir, "photos").apply { mkdirs() }
                val file = File(dir, "receipt-${System.currentTimeMillis()}.jpg")
                val uri = FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.photos",
                    file,
                )
                val capture = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                    putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    addFlags(
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                }
                pendingPhoto = result to file
                try {
                    activity.startActivityForResult(capture, TAKE_PHOTO)
                } catch (e: ActivityNotFoundException) {
                    pendingPhoto = null
                    result.error("unavailable", "No camera app", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Returns true when the result was the contact picker's or the camera's. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == TAKE_PHOTO) {
            val (result, file) = pendingPhoto ?: return true
            pendingPhoto = null
            if (resultCode == Activity.RESULT_OK && file.exists() && file.length() > 0) {
                result.success(file.absolutePath)
            } else {
                file.delete()
                result.success(null)
            }
            return true
        }
        if (requestCode != PICK_PHONE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        val columns = arrayOf(
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
        )
        try {
            activity.contentResolver.query(uri, columns, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    result.success(mapOf("number" to c.getString(0), "name" to c.getString(1)))
                } else {
                    result.success(null)
                }
            } ?: result.success(null)
        } catch (e: SecurityException) {
            result.error("unavailable", "The contact could not be read", null)
        }
        return true
    }

    private companion object {
        const val PICK_PHONE = 4711
        const val TAKE_PHOTO = 4712
    }
}
