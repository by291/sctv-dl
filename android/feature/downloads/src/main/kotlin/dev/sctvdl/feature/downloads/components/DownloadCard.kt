package dev.sctvdl.feature.downloads.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.download.supportedActions
import dev.sctvdl.feature.downloads.downloadProgress
import dev.sctvdl.feature.downloads.downloadStatus
import dev.sctvdl.feature.downloads.label
import dev.sctvdl.ui.media.CoverImage

@Composable
internal fun DownloadCard(
    task: DownloadTask,
    onPlay: (String) -> Unit,
    onShare: (DownloadTask) -> Unit,
    onOpenFile: (DownloadTask) -> Unit,
    onAction: (DownloadAction) -> Unit,
    selecting: Boolean,
    selected: Boolean,
    onToggle: () -> Unit,
    busy: Boolean
) {
    val cover = task.selection?.let { it.content.coverUrl ?: it.programme.coverUrl }
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val actions = supportedActions(task)
    val hasFileMenu = DownloadAction.DeleteFile in actions || DownloadAction.RemoveRecord in actions
    var menu by remember { mutableStateOf(false) }
    OutlinedCard(
        Modifier.widthIn(max = 840.dp).fillMaxWidth().then(
            if (selecting) {
                Modifier.toggleable(selected, enabled = !busy, role = Role.Checkbox) { onToggle() }
            } else {
                Modifier
            }
        )
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (largeText && cover != null) CoverImage(cover, Modifier.fillMaxWidth().aspectRatio(16f / 9f))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (selecting) Checkbox(checked = selected, onCheckedChange = null)
                if (!largeText && cover != null) CoverImage(cover, Modifier.width(112.dp).aspectRatio(16f / 9f))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(task.title, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${task.programmeName} · ${task.broadcastDate} · ${task.actualQuality.label}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (!selecting && hasFileMenu) {
                    Box {
                        IconButton(onClick = {
                            menu = true
                        }, enabled = !busy) { Icon(Icons.Outlined.MoreVert, "更多下载操作") }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            if (task.state == DownloadState.Completed && task.contentUri != null) {
                                DropdownMenuItem(text = { Text("分享") }, onClick = {
                                    menu = false
                                    onShare(task)
                                })
                                DropdownMenuItem(text = { Text("打开文件") }, onClick = {
                                    menu = false
                                    onOpenFile(task)
                                })
                            }
                            listOf(DownloadAction.DeleteFile, DownloadAction.RemoveRecord).filter {
                                it in actions
                            }.forEach { action ->
                                DropdownMenuItem(text = { Text(action.label) }, onClick = {
                                    menu = false
                                    onAction(action)
                                })
                            }
                        }
                    }
                }
            }
            Text(
                downloadStatus(task),
                style = MaterialTheme.typography.labelLarge,
                color = when (task.state) {
                    DownloadState.Failed -> MaterialTheme.colorScheme.error
                    DownloadState.Missing -> MaterialTheme.colorScheme.onSurfaceVariant
                    else -> MaterialTheme.colorScheme.primary
                }
            )
            val showProgress = task.bytes > 0 || task.totalBytes != null || task.state.isActive
            if (task.state != DownloadState.Preparing && showProgress) {
                Text(downloadProgress(task), style = MaterialTheme.typography.bodySmall)
            }
            if (task.state.isActive) {
                val total = task.totalBytes?.takeIf { it > 0 }
                if (total != null) {
                    LinearProgressIndicator(progress = {
                        (task.bytes.toFloat() / total).coerceIn(0f, 1f)
                    }, modifier = Modifier.fillMaxWidth())
                } else if (task.state != DownloadState.Paused) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                if (task.wifiOnly) Text("仅 Wi-Fi 下载", style = MaterialTheme.typography.bodySmall)
                if (task.owner ==
                    DownloadOwner.LegacySystem
                ) {
                    Text("系统下载任务不支持手动暂停", style = MaterialTheme.typography.bodySmall)
                }
            }
            task.reason?.takeIf { task.state in setOf(DownloadState.Failed, DownloadState.Waiting) }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (task.actualQuality !=
                task.requestedQuality
            ) {
                Text("所选清晰度不可用，使用可用版本", style = MaterialTheme.typography.bodySmall)
            }
            if (!selecting) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (task.state == DownloadState.Completed && task.contentUri != null) {
                        FilledTonalButton(onClick = { onPlay(task.id) }, enabled = !busy) { Text("本地播放") }
                    }
                    actions.filter {
                        it !in setOf(DownloadAction.DeleteFile, DownloadAction.RemoveRecord)
                    }.forEach { action ->
                        TextButton(onClick = { onAction(action) }, enabled = !busy) {
                            Text(
                                if (action == DownloadAction.Retry &&
                                    task.state == DownloadState.Failed
                                ) {
                                    "重试"
                                } else {
                                    action.label
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
