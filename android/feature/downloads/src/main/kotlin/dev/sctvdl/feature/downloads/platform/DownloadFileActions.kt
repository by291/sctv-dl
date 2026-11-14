package dev.sctvdl.feature.downloads.platform

import android.app.DownloadManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import dev.sctvdl.domain.download.DownloadTask

internal fun shareDownloadFile(context: Context, task: DownloadTask, onError: (String) -> Unit) {
    val uri = task.contentUri?.let(Uri::parse) ?: return onError("下载文件已不可用")
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "video/mp4"
        putExtra(Intent.EXTRA_STREAM, uri)
    }

    context.launchDownloadChooser(intent, ClipData.newRawUri(task.title, uri), "分享节目视频", onError)
}

internal fun openDownloadFile(context: Context, task: DownloadTask, onError: (String) -> Unit) {
    val uri = task.contentUri?.let(Uri::parse) ?: return onError("下载文件已不可用")
    val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/mp4")

    context.launchDownloadChooser(intent, ClipData.newRawUri(task.title, uri), "打开节目视频", onError)
}

private fun Context.launchDownloadChooser(intent: Intent, clip: ClipData, title: String, onError: (String) -> Unit) {
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.clipData = clip

    try {
        startActivity(Intent.createChooser(intent, title))
    } catch (_: Exception) {
        onError("未找到可以打开视频的应用")
    }
}

internal fun openSystemDownloads(context: Context, onError: (String) -> Unit) {
    try {
        context.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
    } catch (_: Exception) {
        onError("此设备无法打开系统下载，请使用文件管理器查看 Downloads/sctv-dl")
    }
}
