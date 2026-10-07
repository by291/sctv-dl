package dev.sctvdl.app.features.downloads

import android.app.DownloadManager
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import dev.sctvdl.domain.DownloadTask

fun openDownloadFile(context: Context, task: DownloadTask, share: Boolean, onError: (String) -> Unit) {
    val uri = task.contentUri?.let(Uri::parse) ?: return onError("下载文件已不可用")
    val intent = if (share) {
        Intent(Intent.ACTION_SEND).apply {
            type = "video/mp4"
            putExtra(Intent.EXTRA_STREAM, uri)
        }
    } else {
        Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/mp4")
    }
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.clipData = ClipData.newRawUri(task.title, uri)
    try {
        context.startActivity(Intent.createChooser(intent, if (share) "分享节目视频" else "打开节目视频"))
    } catch (
        _: Exception
    ) {
        onError("未找到可以打开视频的应用")
    }
}

fun openSystemDownloads(context: Context, onError: (String) -> Unit) {
    try {
        context.startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
    } catch (
        _: Exception
    ) {
        onError("此设备无法打开系统下载，请使用文件管理器查看 Downloads/sctv-dl")
    }
}
