package dev.sctvdl.flutter

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Owns file-channel work; publication and resolver I/O never run on the UI thread. */
internal class FilesChannel(private val activity: Activity, messenger: BinaryMessenger) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val resolver = activity.contentResolver
    private val channel = MethodChannel(messenger, "dev.sctvdl.flutter/files")

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "consumeNotificationIntent") {
            val cleaned = consumeDownloadNotificationIntent(activity.intent, call.argument<String>("taskId"))
            if (cleaned != null) activity.intent = cleaned
            result.success(cleaned != null)
            return
        }
        if (call.method == "publishRecoverable") {
            publish(call, result)
            return
        }

        val location = call.argument<String>("location")
        if (location == null || !location.startsWith("content://")) {
            result.error("invalid_location", "Expected an owned content URI", null)
            return
        }
        val uri = Uri.parse(location)
        when (call.method) {
            "stat" ->
                executor.execute {
                    val state = stat(uri)
                    activity.runOnUiThread { result.success(state) }
                }
            "delete" -> execute("delete_failed", result) { resolver.delete(uri, null, null) > 0 }
            "share" -> share(uri, call.argument<String>("filename"), result)
            else -> result.notImplemented()
        }
    }

    private fun publish(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        if (source == null || filename == null) {
            result.error("invalid_publication", "Source and planned filename are required", null)
            return
        }
        execute("publication_failed", result) {
            MediaStorePublisher(resolver, activity.packageName, activity.filesDir)
                .publish(File(source), filename)
                .toString()
        }
    }

    private fun execute(code: String, result: MethodChannel.Result, action: () -> Any) {
        executor.execute {
            try {
                val value = action()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error(code, error.message, null) }
            }
        }
    }

    private fun share(uri: Uri, filename: String?, result: MethodChannel.Result) {
        try {
            val intent =
                Intent(Intent.ACTION_SEND).apply {
                    type = "video/mp4"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TITLE, filename)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    clipData = ClipData.newUri(resolver, "video", uri)
                }
            activity.startActivity(Intent.createChooser(intent, "分享视频"))
            result.success(true)
        } catch (error: Exception) {
            result.error("share_failed", error.message, null)
        }
    }

    private fun stat(uri: Uri): Map<String, Any> = try {
        resolver.openFileDescriptor(uri, "r")?.use { descriptor ->
            var size = descriptor.statSize
            if (size < 0) {
                resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) size = cursor.getLong(0)
                }
            }
            buildMap {
                put("exists", true)
                if (size >= 0) put("bytes", size)
            }
        } ?: mapOf("exists" to false)
    } catch (_: Exception) {
        mapOf("exists" to false)
    }

    override fun close() {
        channel.setMethodCallHandler(null)
        // Finish accepted publication work; shutdown does not cancel queued I/O.
        executor.shutdown()
    }
}
