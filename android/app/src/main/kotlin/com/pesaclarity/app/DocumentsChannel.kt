package com.pesaclarity.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Storage Access Framework for backups: a folder the user picks once (phone, SD card or any
 * document provider), single files to restore from, and "save as" for the recovery key.
 * Needs no storage permission; access is granted per folder or file by the system picker.
 */
class DocumentsChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methods = MethodChannel(messenger, "com.pesaclarity.app/documents")
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pending? = null

    private class Pending(val requestCode: Int, val result: MethodChannel.Result, val source: String?)

    init {
        methods.setMethodCallHandler(this)
    }

    fun dispose() {
        methods.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> launch(PICK_FOLDER, Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), result)
            "pickFile" ->
                launch(
                    PICK_FILE,
                    Intent(Intent.ACTION_OPEN_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("*/*"),
                    result,
                )
            "saveAs" -> {
                val source = call.argument<String>("source")
                val name = call.argument<String>("name")
                val mimeType = call.argument<String>("mimeType")
                if (source == null || name == null || mimeType == null) {
                    result.error("bad_args", "source, name and mimeType are required", null)
                    return
                }
                launch(
                    SAVE_AS,
                    Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType(mimeType)
                        .putExtra(Intent.EXTRA_TITLE, name),
                    result,
                    source,
                )
            }
            "canWrite" -> {
                val uri = call.argument<String>("uri")
                result.success(uri != null && hasTreeAccess(Uri.parse(uri)))
            }
            "writeFile" -> {
                val tree = Uri.parse(call.argument<String>("treeUri") ?: "")
                val name = call.argument<String>("name") ?: ""
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                val source = call.argument<String>("source") ?: ""
                background(result) {
                    writeFile(tree, name, mimeType, File(source))
                    null
                }
            }
            "listFiles" -> {
                val tree = Uri.parse(call.argument<String>("treeUri") ?: "")
                background(result) { listFiles(tree) }
            }
            "copyToFile" -> {
                val uri = Uri.parse(call.argument<String>("uri") ?: "")
                val destination = call.argument<String>("destination") ?: ""
                background(result) {
                    copyToFile(uri, File(destination))
                    null
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Returns true if [requestCode] belonged to this channel. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        val request = pending ?: return false
        if (request.requestCode != requestCode) return false
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            request.result.success(if (requestCode == SAVE_AS) false else null)
            return true
        }
        when (requestCode) {
            PICK_FOLDER ->
                background(request.result) {
                    activity.contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                    val folder =
                        DocumentsContract.buildDocumentUriUsingTree(
                            uri,
                            DocumentsContract.getTreeDocumentId(uri),
                        )
                    mapOf("uri" to uri.toString(), "name" to displayName(folder))
                }
            PICK_FILE ->
                background(request.result) {
                    var name: String? = null
                    var size: Long? = null
                    activity.contentResolver
                        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
                        ?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                name = cursor.getString(0)
                                if (!cursor.isNull(1)) size = cursor.getLong(1)
                            }
                        }
                    mapOf("uri" to uri.toString(), "name" to (name ?: ""), "size" to size)
                }
            SAVE_AS ->
                background(request.result) {
                    copy(File(request.source ?: ""), uri)
                    true
                }
        }
        return true
    }

    private fun launch(requestCode: Int, intent: Intent, result: MethodChannel.Result, source: String? = null) {
        if (pending != null) {
            result.error("busy", "A picker is already showing", null)
            return
        }
        try {
            pending = Pending(requestCode, result, source)
            activity.startActivityForResult(intent, requestCode)
        } catch (e: ActivityNotFoundException) {
            pending = null
            result.error("unavailable", "This phone has no document picker", null)
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: SecurityException) {
                main.post { result.error("no_access", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("io_failed", e.message, null) }
            }
        }
    }

    private fun hasTreeAccess(tree: Uri) =
        activity.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission && it.isWritePermission
        }

    private fun writeFile(tree: Uri, name: String, mimeType: String, source: File) {
        if (!hasTreeAccess(tree)) throw SecurityException("Folder access was removed")
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val document =
            DocumentsContract.createDocument(activity.contentResolver, parent, mimeType, name)
                ?: throw IllegalStateException("Could not create $name")
        try {
            copy(source, document)
        } catch (e: Exception) {
            DocumentsContract.deleteDocument(activity.contentResolver, document)
            throw e
        }
    }

    private fun listFiles(tree: Uri): List<Map<String, Any?>> {
        if (!hasTreeAccess(tree)) throw SecurityException("Folder access was removed")
        val children =
            DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val projection =
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
        val files = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(children, projection, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0) ?: continue
                files +=
                    mapOf(
                        "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                        "name" to (cursor.getString(1) ?: ""),
                        "size" to (if (cursor.isNull(2)) null else cursor.getLong(2)),
                        "modifiedMillis" to (if (cursor.isNull(3)) null else cursor.getLong(3)),
                    )
            }
        }
        return files
    }

    private fun copyToFile(uri: Uri, destination: File) {
        val input =
            activity.contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Could not open the file")
        input.use { from -> destination.outputStream().use { to -> from.copyTo(to) } }
    }

    private fun copy(source: File, target: Uri) {
        val output =
            activity.contentResolver.openOutputStream(target, "w")
                ?: throw IllegalStateException("Could not write the file")
        output.use { to -> source.inputStream().use { from -> from.copyTo(to) } }
    }

    private fun displayName(document: Uri): String? =
        activity.contentResolver
            .query(document, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private companion object {
        const val PICK_FOLDER = 4711
        const val PICK_FILE = 4712
        const val SAVE_AS = 4713
    }
}
