package dev.sctvdl.flutter

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.io.File

class MainActivity : FlutterActivity() {
    private val filesExecutor = Executors.newSingleThreadExecutor()

    override fun onNewIntent(intent: Intent) {
        // Publish the new launch identity before plugins deliver asynchronous taps.
        setIntent(intent)
        super.onNewIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.sctvdl.flutter/files")
            .setMethodCallHandler { call, result ->
                if (call.method == "consumeNotificationIntent") {
                    val cleaned = consumeDownloadNotificationIntent(intent, call.argument<String>("taskId"))
                    if (cleaned != null) setIntent(cleaned)
                    result.success(cleaned != null)
                    return@setMethodCallHandler
                }
                if (call.method == "publishRecoverable") {
                    val source = call.argument<String>("sourcePath")
                    val filename = call.argument<String>("filename")
                    if (source == null || filename == null) {
                        result.error("invalid_publication", "Source and planned filename are required", null)
                    } else filesExecutor.execute {
                        try {
                            val uri = MediaStorePublisher(contentResolver, packageName, filesDir).publish(File(source), filename)
                            runOnUiThread { result.success(uri.toString()) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("publication_failed", error.message, null) }
                        }
                    }
                    return@setMethodCallHandler
                }
                val location = call.argument<String>("location")
                if (location == null || !location.startsWith("content://")) {
                    result.error("invalid_location", "Expected an owned content URI", null)
                    return@setMethodCallHandler
                }
                val uri = Uri.parse(location)
                when (call.method) {
                    "stat" -> filesExecutor.execute {
                        val state = stat(uri)
                        runOnUiThread { result.success(state) }
                    }
                    "delete" -> filesExecutor.execute {
                        try {
                            val deleted = contentResolver.delete(uri, null, null) > 0
                            runOnUiThread { result.success(deleted) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("delete_failed", error.message, null) }
                        }
                    }
                    "share" -> {
                        try {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "video/mp4"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("filename"))
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                clipData = android.content.ClipData.newUri(contentResolver, "video", uri)
                            }
                            startActivity(Intent.createChooser(intent, "分享视频"))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("share_failed", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun stat(uri: Uri): Map<String, Any> = try {
        contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
            var size = descriptor.statSize
            if (size < 0) {
                contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
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

    override fun onDestroy() {
        filesExecutor.shutdown()
        super.onDestroy()
    }
}
