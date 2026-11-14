package dev.sctvdl.flutter

import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import java.io.File

private const val MAX_FILENAME_BYTES = 255

/** Publishes one attempt's unique filename and keeps its private source available for recovery. */
internal class MediaStorePublisher(
    private val resolver: ContentResolver,
    private val ownerPackage: String,
    private val privateRoot: File,
) {
    private val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    private val destination = Environment.DIRECTORY_DOWNLOADS + "/sctv-dl/"

    // API 29 needs this URI form; it remains supported on newer providers. A
    // normal query can omit pending rows even when this package created them.
    @Suppress("DEPRECATION")
    private val recoverableCollection = MediaStore.setIncludePending(collection)

    private data class OwnedRow(
        val uri: Uri,
        val isPending: Boolean,
    )

    private data class PublishedMetadata(
        val isPending: Boolean,
        val packageName: String?,
        val filename: String?,
        val relativePath: String?,
    )

    /** Recovers an interrupted publication or returns the verified public URI. */
    fun publish(
        source: File,
        filename: String,
    ): Uri {
        val canonical = validateSource(source, filename)
        val length = canonical.length()
        val rows = findOwned(filename)

        // Full-length pending rows can still represent an interrupted copy.
        for (row in rows.filter { it.isPending }) {
            check(resolver.delete(row.uri, null, null) > 0) {
                "Unable to remove interrupted publication"
            }
        }

        val visible = rows.firstOrNull { !it.isPending }
        if (visible != null) {
            // Dart may retry after publication but before the URI was saved.
            check(actualLength(visible.uri) == length) {
                "A visible file already owns the planned filename"
            }
            return visible.uri
        }

        val created = reservePending(filename)
        try {
            copyBytes(canonical, created)
            check(actualLength(created) == length) { "Publication size verification failed" }

            makeVisible(created)
            verifyPublication(created, filename, length)
            return created
        } catch (error: Exception) {
            // Existing visible files and the private source survive this rollback.
            try {
                check(resolver.delete(created, null, null) > 0) {
                    "Unable to clean failed publication"
                }
            } catch (cleanup: Exception) {
                error.addSuppressed(cleanup)
            }
            throw error
        }
    }

    private fun validateSource(
        source: File,
        filename: String,
    ): File {
        val isSimpleName = filename.isNotBlank() && filename != "." && filename != ".."
        val hasInvalidCharacters =
            filename.contains('/') || filename.contains('\\') || filename.contains('\u0000')
        val fitsFilenameBudget = filename.toByteArray(Charsets.UTF_8).size <= MAX_FILENAME_BYTES
        require(isSimpleName && !hasInvalidCharacters && fitsFilenameBudget) {
            "Invalid planned filename"
        }

        val canonical = source.canonicalFile
        val isPrivate = canonical.path.startsWith(privateRoot.canonicalPath + File.separator)
        require(isPrivate && canonical.isFile) { "Publication requires an app-owned staging file" }

        return canonical
    }

    private fun findOwned(filename: String): List<OwnedRow> {
        val rows = mutableListOf<OwnedRow>()
        val projection =
            arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.IS_PENDING,
                MediaStore.MediaColumns.OWNER_PACKAGE_NAME,
            )
        val selection =
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? AND " +
                "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
        val matches =
            resolver.query(
                recoverableCollection,
                projection,
                selection,
                arrayOf(filename, destination),
                null,
            )

        checkNotNull(matches) { "Unable to query existing publications" }.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
            val pendingColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.IS_PENDING)
            val ownerColumn =
                cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
            while (cursor.moveToNext()) {
                // Provider-visible files from another app are not ours to repair.
                if (cursor.getString(ownerColumn) != ownerPackage) {
                    continue
                }

                val uri = ContentUris.withAppendedId(collection, cursor.getLong(idColumn))
                rows += OwnedRow(uri = uri, isPending = cursor.getInt(pendingColumn) != 0)
            }
        }

        return rows
    }

    private fun reservePending(filename: String): Uri {
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                put(MediaStore.MediaColumns.RELATIVE_PATH, destination)
                put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

        return checkNotNull(resolver.insert(collection, values)) {
            "Unable to reserve Downloads publication"
        }
    }

    private fun copyBytes(
        source: File,
        uri: Uri,
    ) {
        source.inputStream().use { input ->
            val stream =
                checkNotNull(resolver.openOutputStream(uri, "w")) {
                    "Unable to open reserved publication"
                }
            stream.use { output ->
                input.copyTo(output)
                output.flush()
            }
        }
    }

    private fun actualLength(uri: Uri): Long {
        val descriptor =
            checkNotNull(resolver.openFileDescriptor(uri, "r")) {
                "Unable to open publication for verification"
            }
        return descriptor.use { it.statSize }
    }

    private fun makeVisible(uri: Uri) {
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
        check(resolver.update(uri, values, null, null) == 1) {
            "Unable to make publication visible"
        }
    }

    private fun verifyPublication(
        uri: Uri,
        filename: String,
        length: Long,
    ) {
        // MediaStore can rename the file when it becomes visible. Dart may drop the
        // recovery source after saving the URI, so verify the committed location first.
        val projection =
            arrayOf(
                MediaStore.MediaColumns.IS_PENDING,
                MediaStore.MediaColumns.OWNER_PACKAGE_NAME,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.RELATIVE_PATH,
            )
        val metadata =
            resolver.query(uri, projection, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    readMetadata(cursor)
                } else {
                    null
                }
            }

        val expected =
            PublishedMetadata(
                isPending = false,
                packageName = ownerPackage,
                filename = filename,
                relativePath = destination,
            )
        check(metadata == expected && actualLength(uri) == length) {
            "Published destination could not be verified: $metadata"
        }
    }

    private fun readMetadata(cursor: Cursor): PublishedMetadata {
        val pendingColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.IS_PENDING)
        val ownerColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.OWNER_PACKAGE_NAME)
        val filenameColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
        val pathColumn = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.RELATIVE_PATH)
        return PublishedMetadata(
            isPending = cursor.getInt(pendingColumn) != 0,
            packageName = cursor.getString(ownerColumn),
            filename = cursor.getString(filenameColumn),
            relativePath = cursor.getString(pathColumn),
        )
    }
}
