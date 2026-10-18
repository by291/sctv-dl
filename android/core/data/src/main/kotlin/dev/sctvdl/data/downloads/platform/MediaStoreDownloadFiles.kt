package dev.sctvdl.data.downloads.platform

import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.sctvdl.data.di.DownloadFileConsentRegistry
import dev.sctvdl.data.downloads.managed.ManagedTransferGateway
import dev.sctvdl.domain.download.DownloadTask
import java.io.IOException
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

internal class MediaStoreDownloadFiles @Inject constructor(
    @ApplicationContext private val context: Context,
    private val transfers: ManagedTransferGateway,
    private val consents: DownloadFileConsentRegistry
) : PublicDownloadFiles {
    private val resolver = context.contentResolver
    private val directory = Environment.DIRECTORY_DOWNLOADS + "/sctv-dl/"

    override suspend fun reserve(task: DownloadTask): String = withContext(Dispatchers.IO) {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, task.filename)
            put(MediaStore.Downloads.MIME_TYPE, "video/mp4")
            put(MediaStore.Downloads.RELATIVE_PATH, directory)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)?.toString()
            ?: throw IOException("Cannot reserve public video")
    }

    override suspend fun copyCached(task: DownloadTask, pendingUri: String): Long = withContext(Dispatchers.IO) {
        transfers.openCached(task).use { source ->
            val output =
                resolver.openOutputStream(Uri.parse(pendingUri), "wt") ?: throw IOException("Cannot write public video")
            output.use { destination ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val count = source.read(buffer)
                    if (count < 0) break
                    destination.write(buffer, 0, count)
                    total += count
                }
                total
            }
        }
    }

    override suspend fun finalize(pendingUri: String): Unit = withContext(Dispatchers.IO) {
        val changed = resolver.update(
            Uri.parse(pendingUri),
            ContentValues().apply {
                put(MediaStore.Downloads.IS_PENDING, 0)
            },
            null,
            null
        )
        check(changed == 1) { "Pending public video disappeared" }
    }

    override suspend fun isReadable(uri: String): Boolean = withContext(Dispatchers.IO) {
        try {
            resolver.openInputStream(Uri.parse(uri))?.use { it.read() != -1 } == true
        } catch (
            _: IOException
        ) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    override suspend fun isPublished(task: DownloadTask, uri: String): Boolean = withContext(Dispatchers.IO) {
        val parsed = Uri.parse(uri)
        val finalized = resolver.query(parsed, arrayOf(MediaStore.Downloads.IS_PENDING), null, null, null)?.use {
            it.moveToFirst() && it.getInt(0) == 0
        } == true
        if (!finalized) return@withContext false
        // Android 10 updates the provider's SIZE column asynchronously after close/finalization.
        // Verify the actual owned file, not delayed scanner metadata.
        val bytes = resolver.openFileDescriptor(parsed, "r")?.use { it.statSize } ?: return@withContext false
        bytes > 0 && (task.totalBytes == null || bytes == task.totalBytes) && isReadable(uri)
    }

    override suspend fun delete(uri: String): FileDeleteResult = withContext(Dispatchers.IO) {
        val parsed = Uri.parse(uri)
        try {
            if (resolver.delete(parsed, null, null) > 0) FileDeleteResult.Deleted else FileDeleteResult.Missing
        } catch (failure: SecurityException) {
            val sender = when {
                Build.VERSION.SDK_INT >= 30 -> MediaStore.createDeleteRequest(resolver, listOf(parsed)).intentSender
                failure is RecoverableSecurityException -> failure.userAction.actionIntent.intentSender
                else -> throw failure
            }
            FileDeleteResult.ConsentRequired(consents.register(uri, sender))
        }
    }

    override suspend fun findPlanned(task: DownloadTask): List<String> = withContext(Dispatchers.IO) {
        val projection = arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.OWNER_PACKAGE_NAME)
        val selection = "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?"
        val arguments = arrayOf(task.filename, directory)
        // Collection queries hide pending rows by default, including the row we must recover after a crash.
        val cursor = if (Build.VERSION.SDK_INT >= 30) {
            val query = android.os.Bundle().apply {
                putString(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(android.content.ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arguments)
                putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
            }
            resolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI, projection, query, null)
        } else {
            @Suppress("DEPRECATION")
            val includingPending = MediaStore.setIncludePending(MediaStore.Downloads.EXTERNAL_CONTENT_URI)
            resolver.query(includingPending, projection, selection, arguments, null)
        }
        cursor?.use {
            buildList {
                while (it.moveToNext()) {
                    if (it.getString(1) == context.packageName) {
                        add(
                            ContentUris.withAppendedId(
                                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                it.getLong(0)
                            ).toString()
                        )
                    }
                }
            }
        }.orEmpty()
    }
}
