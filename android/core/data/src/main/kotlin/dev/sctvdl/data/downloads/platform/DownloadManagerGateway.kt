package dev.sctvdl.data.downloads.platform

import android.app.DownloadManager
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Environment
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import java.io.File
import java.io.IOException
import javax.inject.Inject

internal class DownloadManagerGateway @Inject constructor(@ApplicationContext private val context: Context) :
    PlatformDownloadGateway {
    private val manager = context.getSystemService(DownloadManager::class.java)

    override fun destinationFor(filename: String): String = Uri.fromFile(
        File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "sctv-dl/$filename"
        )
    ).toString()

    override suspend fun enqueue(request: PlatformDownloadRequest): Long = manager.enqueue(
        DownloadManager.Request(Uri.parse(request.url))
            .setTitle(request.title).setDescription(
                "Downloads/sctv-dl/${request.filename}\n" +
                    "蜀台回看 · ${if (request.wifiOnly) "仅 Wi-Fi" else "Wi-Fi 或移动网络"}"
            )
            .setMimeType("video/mp4").addRequestHeader("Referer", UpstreamUrlPolicy.REFERER)
            .setDestinationInExternalPublicDir(
                Environment.DIRECTORY_DOWNLOADS,
                "sctv-dl/${request.filename}"
            )
            .setAllowedNetworkTypes(
                if (request.wifiOnly) {
                    DownloadManager.Request.NETWORK_WIFI
                } else {
                    DownloadManager.Request.NETWORK_WIFI or DownloadManager.Request.NETWORK_MOBILE
                }
            )
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
    )

    override suspend fun query(ids: List<Long>) =
        if (ids.isEmpty()) emptyList() else query(DownloadManager.Query().setFilterById(*ids.toLongArray()))

    override suspend fun queryOwned() = query(DownloadManager.Query())

    private fun query(query: DownloadManager.Query): List<SystemDownloadSnapshot> = manager.query(query).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                val id = cursor.long(DownloadManager.COLUMN_ID)
                val status = cursor.long(DownloadManager.COLUMN_STATUS).toInt()
                val reason = cursor.long(DownloadManager.COLUMN_REASON).toInt()
                val state = when (status) {
                    DownloadManager.STATUS_PENDING -> DownloadState.Pending
                    DownloadManager.STATUS_RUNNING -> DownloadState.Running
                    DownloadManager.STATUS_PAUSED -> DownloadState.Waiting
                    DownloadManager.STATUS_SUCCESSFUL -> DownloadState.Completed
                    else -> DownloadState.Failed
                }
                val cause = when {
                    state == DownloadState.Waiting -> when (reason) {
                        DownloadManager.PAUSED_WAITING_FOR_NETWORK -> DownloadReason.Network to "等待网络连接"
                        DownloadManager.PAUSED_QUEUED_FOR_WIFI -> DownloadReason.Wifi to "等待 Wi-Fi 连接"
                        DownloadManager.PAUSED_WAITING_TO_RETRY -> DownloadReason.Retry to "系统等待重试"
                        else -> DownloadReason.Unknown to "系统暂时挂起"
                    }
                    state == DownloadState.Failed -> when (reason) {
                        DownloadManager.ERROR_INSUFFICIENT_SPACE -> DownloadReason.Storage to "存储空间不足"
                        DownloadManager.ERROR_DEVICE_NOT_FOUND -> DownloadReason.Storage to "下载目录不可用"
                        DownloadManager.ERROR_FILE_ALREADY_EXISTS -> DownloadReason.Storage to "目标文件已存在"
                        else -> DownloadReason.Http to "下载失败（系统代码 $reason）"
                    }
                    else -> null
                }
                add(
                    SystemDownloadSnapshot(
                        id,
                        cursor.string(DownloadManager.COLUMN_URI).orEmpty(),
                        cursor.string(DownloadManager.COLUMN_LOCAL_URI)
                            ?: plannedDestination(cursor.string(DownloadManager.COLUMN_DESCRIPTION)),
                        state,
                        cursor.long(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR).coerceAtLeast(0),
                        cursor.long(DownloadManager.COLUMN_TOTAL_SIZE_BYTES).takeIf { it > 0 },
                        if (state == DownloadState.Completed) manager.getUriForDownloadedFile(id)?.toString() else null,
                        cause?.second,
                        cause?.first
                    )
                )
            }
        }
    }

    override suspend fun remove(id: Long) {
        manager.remove(id)
    }

    private fun plannedDestination(description: String?): String? {
        // The provider may not expose a local URI until the waiting job creates its file.
        val path = description?.substringBefore('\n') ?: return null
        val prefix = "Downloads/sctv-dl/"
        if (!path.startsWith(prefix)) return null
        val filename = path.removePrefix(prefix)
        if (filename.isBlank() || filename in setOf(".", "..") ||
            filename.contains(Regex("[\\p{Cntrl}/\\\\]"))
        ) {
            return null
        }
        return destinationFor(filename)
    }

    override suspend fun isAvailable(uri: String): Boolean = try {
        val target = Uri.parse(uri)
        target.scheme == "content" && context.contentResolver.openFileDescriptor(
            target,
            "r"
        )?.use { true } == true
    } catch (_: IOException) {
        false
    } catch (_: SecurityException) {
        false
    }

    private fun Cursor.long(column: String) = getLong(getColumnIndexOrThrow(column))

    private fun Cursor.string(column: String) = getString(getColumnIndexOrThrow(column))
}
