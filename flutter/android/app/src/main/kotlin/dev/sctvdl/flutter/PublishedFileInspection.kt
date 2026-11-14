package dev.sctvdl.flutter

import android.content.ContentResolver
import android.net.Uri
import android.provider.BaseColumns
import android.provider.OpenableColumns
import java.io.FileNotFoundException

/** Reports a confirmed missing row separately from a failed probe. */
internal fun inspectPublishedFile(
    resolver: ContentResolver,
    uri: Uri,
): Map<String, Any> {
    val descriptor =
        try {
            resolver.openFileDescriptor(uri, "r")
        } catch (error: FileNotFoundException) {
            // A provider can throw for an existing row whose bytes cannot be opened.
            // Only a successful empty lookup lets Dart mark the download as missing.
            val rows = resolver.query(uri, arrayOf(BaseColumns._ID), null, null, null)
            if (rows?.use { !it.moveToFirst() } == true) {
                return mapOf("exists" to false)
            }
            throw error
        }
    val bytes =
        checkNotNull(descriptor) {
            "Content provider did not return a file descriptor"
        }.use { it.statSize }

    val knownBytes = bytes.takeIf { it >= 0 } ?: queryPublishedSize(resolver, uri)
    return buildMap {
        put("exists", true)
        if (knownBytes != null) {
            put("bytes", knownBytes)
        }
    }
}

private fun queryPublishedSize(
    resolver: ContentResolver,
    uri: Uri,
): Long? {
    // A successfully opened descriptor proves readability even without a byte count.
    val rows = resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
    return rows?.use { cursor ->
        val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
        if (sizeColumn >= 0 && cursor.moveToFirst() && !cursor.isNull(sizeColumn)) {
            cursor.getLong(sizeColumn).takeIf { it >= 0 }
        } else {
            null
        }
    }
}
