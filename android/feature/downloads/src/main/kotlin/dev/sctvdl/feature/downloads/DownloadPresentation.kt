package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import java.util.Locale

internal fun downloadStatus(task: DownloadTask): String = when (task.state) {
    DownloadState.Preparing -> "检查视频"
    DownloadState.Pending -> "等待下载"
    DownloadState.Running -> "正在下载"
    DownloadState.Waiting -> when (task.reasonCode) {
        DownloadReason.Wifi -> "等待 Wi-Fi"
        DownloadReason.Network -> "等待网络"
        else -> "等待系统重试"
    }
    DownloadState.Completed -> "已完成"
    DownloadState.Failed -> "下载失败"
    DownloadState.Cancelled -> "已取消"
    DownloadState.Missing -> "文件已移除"
}

internal fun downloadProgress(task: DownloadTask): String {
    val total = task.totalBytes?.takeIf { it > 0 }
    return if (total == null) {
        "已下载 ${formatBytes(task.bytes)}"
    } else {
        "${formatBytes(task.bytes)} / ${formatBytes(total)}"
    }
}

private fun formatBytes(value: Long): String {
    val bytes = value.coerceAtLeast(0)
    val (amount, unit) = when {
        bytes >= 1L shl 30 -> bytes.toDouble() / (1L shl 30) to "GiB"
        bytes >= 1L shl 20 -> bytes.toDouble() / (1L shl 20) to "MiB"
        bytes >= 1L shl 10 -> bytes.toDouble() / (1L shl 10) to "KiB"
        else -> return "$bytes B"
    }
    return String.format(Locale.ROOT, "%.1f %s", amount, unit)
}
