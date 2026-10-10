package dev.sctvdl.feature.downloads.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.feature.downloads.downloadProgress
import dev.sctvdl.feature.downloads.downloadStatus

@Composable
internal fun DownloadCard(
    task: DownloadTask,
    onCancel: (String) -> Unit,
    onRetry: (String) -> Unit,
    onRemove: (String) -> Unit,
    onPlay: (String) -> Unit,
    onShare: (DownloadTask) -> Unit,
    onOpenFile: (DownloadTask) -> Unit
) {
    OutlinedCard(Modifier.widthIn(max = 840.dp).fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(task.title, style = MaterialTheme.typography.titleMedium)
            Text(
                "${task.broadcastDate} · ${if (task.actualQuality == Quality.Standard) "标清" else "流畅"}${if (task.wifiOnly) " · 仅 Wi-Fi" else ""}",

                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                downloadStatus(task),
                style = MaterialTheme.typography.labelLarge,
                color = if (task.state ==
                    DownloadState.Failed ||
                    task.state == DownloadState.Missing
                ) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.primary
                }
            )
            if (task.state != DownloadState.Preparing) {
                Text(downloadProgress(task), style = MaterialTheme.typography.bodySmall)
            }
            if (task.state.isActive) {
                val total = task.totalBytes?.takeIf { it > 0 }
                if (total == null ||
                    task.state == DownloadState.Preparing
                ) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                } else {
                    LinearProgressIndicator(progress = {
                        (task.bytes.toDouble() / total).toFloat().coerceIn(0f, 1f)
                    }, modifier = Modifier.fillMaxWidth())
                }
            }
            task.reason?.takeIf {
                task.state == DownloadState.Failed ||
                    task.state == DownloadState.Waiting
            }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            if (task.actualQuality != task.requestedQuality) {
                Text("所选清晰度不可用，已保存可用版本", style = MaterialTheme.typography.bodySmall)
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when {
                    task.state.isActive -> TextButton(onClick = {
                        onCancel(task.id)
                    }) { Text("取消") }
                    task.state == DownloadState.Completed && task.contentUri != null -> {
                        FilledTonalButton(onClick = { onPlay(task.id) }) { Text("本地播放") }
                        TextButton(onClick = { onShare(task) }) { Text("分享") }
                        TextButton(onClick = { onOpenFile(task) }) { Text("打开文件") }
                    }
                    else -> FilledTonalButton(onClick = { onRetry(task.id) }) {
                        Text(
                            if (task.state == DownloadState.Missing) {
                                "重新下载"
                            } else {
                                "重试"
                            }
                        )
                    }
                }
                if (!task.state.isActive) {
                    TextButton(onClick = {
                        onRemove(task.id)
                    }) { Text("移除记录") }
                }
            }
        }
    }
}
