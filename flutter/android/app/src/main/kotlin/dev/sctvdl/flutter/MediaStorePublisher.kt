package dev.sctvdl.flutter

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/** Publishes one attempt's unique filename. Private bytes survive every failure. */
internal class MediaStorePublisher(
    private val resolver: ContentResolver,
    private val ownerPackage: String,
    private val privateRoot: File,
) {
    private val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    // API 29 needs this URI form; it remains supported on newer providers. A
    // normal query can omit pending rows even when this package created them.
    @Suppress("DEPRECATION")
    private val recoverableCollection = MediaStore.setIncludePending(collection)
    private val destination = Environment.DIRECTORY_DOWNLOADS + "/sctv-dl/"

    fun publish(source: File, filename: String): Uri {
        require(filename.isNotBlank() && filename != "." && filename != ".." &&
            !filename.contains('/') && !filename.contains('\\') && !filename.contains('\u0000') &&
            filename.toByteArray(Charsets.UTF_8).size <= 255) { "Invalid planned filename" }
        val canonical = source.canonicalFile
        require(canonical.path.startsWith(privateRoot.canonicalPath + File.separator) && canonical.isFile) {
            "Publication requires an app-owned staging file"
        }
        val length = canonical.length()
        val existing = findOwned(filename)
        for (row in existing.filter { it.pending }) {
            check(resolver.delete(row.uri, null, null) > 0) { "Unable to remove interrupted publication" }
        }
        existing.firstOrNull { !it.pending }?.let { row ->
            check(actualLength(row.uri) == length) { "A visible file already owns the planned filename" }
            return row.uri
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
            put(MediaStore.MediaColumns.RELATIVE_PATH, destination)
            put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val created = checkNotNull(resolver.insert(collection, values)) {
            "Unable to reserve Downloads publication"
        }
        try {
            canonical.inputStream().use { input ->
                checkNotNull(resolver.openOutputStream(created, "w")) { "Unable to open reserved publication" }.use { output ->
                    input.copyTo(output)
                    output.flush()
                }
            }
            check(actualLength(created) == length) { "Publication size verification failed" }
            val visible = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            check(resolver.update(created, visible, null, null) == 1) { "Unable to make publication visible" }
            val projection = arrayOf(MediaStore.MediaColumns.IS_PENDING, MediaStore.MediaColumns.OWNER_PACKAGE_NAME,
                MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.RELATIVE_PATH)
            val metadata = resolver.query(created, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) listOf(cursor.getInt(0).toString(), cursor.getString(1), cursor.getString(2), cursor.getString(3)) else null
            }
            check(metadata != null && metadata[0] == "0" && metadata[1] == ownerPackage && metadata[2] == filename && metadata[3] == destination && actualLength(created) == length) {
                "Published destination could not be verified: $metadata"
            }
            return created
        } catch (error: Exception) {
            // Only this call's newly inserted row is removed. Existing visible
            // files and the private source are never deleted on copy failure.
            try {
                check(resolver.delete(created, null, null) > 0) { "Unable to clean failed publication" }
            } catch (cleanup: Exception) {
                error.addSuppressed(cleanup)
            }
            throw error
        }
    }

    private data class Row(val uri: Uri, val pending: Boolean)

    private fun findOwned(filename: String): List<Row> {
        val rows = mutableListOf<Row>()
        val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.IS_PENDING,
            MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
        resolver.query(recoverableCollection, projection,
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND ${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(filename, destination), null)?.use { cursor ->
            while (cursor.moveToNext()) {
                // Provider-visible files from another app are not ours to repair.
                if (cursor.getString(2) != ownerPackage) continue
                rows += Row(ContentUris.withAppendedId(collection, cursor.getLong(0)), cursor.getInt(1) != 0)
            }
        }
        return rows
    }

    private fun actualLength(uri: Uri): Long =
        resolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: -1L
}
