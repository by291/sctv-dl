package dev.sctvdl.flutter

import android.app.Activity
import android.content.ClipData
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Owns file-channel work; publication and resolver I/O stay off the UI thread. */
internal class FilesChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val resolver = activity.contentResolver
    private val channel = MethodChannel(messenger, "dev.sctvdl.flutter/files")

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "consumeNotificationIntent" -> {
                val taskId = call.argument<String>("taskId")
                val cleaned = consumeDownloadNotificationIntent(activity.intent, taskId)
                if (cleaned != null) {
                    activity.intent = cleaned
                }
                result.success(cleaned != null)
            }
            "publishRecoverable" -> publish(call, result)
            "stat", "delete", "share" -> handlePublishedFile(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handlePublishedFile(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val location = call.argument<String>("location")
        val uri = location?.let(Uri::parse)
        if (uri?.scheme != ContentResolver.SCHEME_CONTENT || uri.authority.isNullOrEmpty()) {
            result.error("invalid_location", "Expected an owned content URI", null)
            return
        }

        when (call.method) {
            "stat" -> execute("stat_failed", result) { inspectPublishedFile(resolver, uri) }
            "delete" -> execute("delete_failed", result) { resolver.delete(uri, null, null) > 0 }
            "share" -> share(uri, call.argument<String>("filename"), result)
        }
    }

    private fun publish(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val source = call.argument<String>("sourcePath")
        val filename = call.argument<String>("filename")
        if (source == null || filename == null) {
            result.error("invalid_publication", "Source and planned filename are required", null)
            return
        }

        execute("publication_failed", result) {
            val publisher = MediaStorePublisher(resolver, activity.packageName, activity.filesDir)
            publisher.publish(File(source), filename).toString()
        }
    }

    private fun execute(
        code: String,
        result: MethodChannel.Result,
        action: () -> Any,
    ) {
        executor.execute {
            try {
                val value = action()
                activity.runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                activity.runOnUiThread { result.error(code, error.message, null) }
            }
        }
    }

    private fun share(
        uri: Uri,
        filename: String?,
        result: MethodChannel.Result,
    ) {
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

    /** Stops intake while allowing already accepted file operations to finish. */
    override fun close() {
        try {
            channel.setMethodCallHandler(null)
        } finally {
            // Cancelling accepted publication work can leave a half-written pending row.
            executor.shutdown()
        }
    }
}
