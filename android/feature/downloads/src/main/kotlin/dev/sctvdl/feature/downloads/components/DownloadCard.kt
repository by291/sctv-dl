package dev.sctvdl.feature.downloads.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.download.supportedActions
import dev.sctvdl.feature.downloads.downloadProgress
import dev.sctvdl.feature.downloads.downloadSize
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
    busy: Boolean,
    onLongPress: (() -> Unit)? = null
) {
    val colours = MaterialTheme.colorScheme
    val actions = supportedActions(task)
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val selectOnLongPress by rememberUpdatedState(onLongPress)
    val interactionModifier = if (selecting) {
        Modifier.toggleable(selected, enabled = !busy, role = Role.Checkbox) { onToggle() }
            .semantics { contentDescription = "${if (selected) "取消选择" else "选择"} ${task.title}" }
    } else if (!busy && onLongPress != null) {
        // Progress updates retain the gesture, but a replacement attempt cancels it before selection.
        Modifier.pointerInput(task.id, task.attemptId) {
            detectTapGestures(onLongPress = { selectOnLongPress?.invoke() })
        }.semantics {
            onLongClick(label = "批量管理") {
                selectOnLongPress?.invoke()
                true
            }
        }
    } else {
        Modifier
    }

    OutlinedCard(
        modifier = Modifier.fillMaxWidth().then(interactionModifier),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.outlinedCardColors(
            containerColor = if (selecting && selected) colours.primaryContainer else colours.surfaceContainerLow
        ),
        border = BorderStroke(
            1.dp,
            if (selecting && selected) colours.primary else colours.outlineVariant.copy(alpha = .5f)
        )
    ) {
        Column(Modifier.padding(start = 16.dp, top = 12.dp, end = 12.dp, bottom = 8.dp)) {
            DownloadCardHeader(task, largeText) {
                if (selecting) {
                    Checkbox(
                        checked = selected,
                        onCheckedChange = null,
                        enabled = !busy,
                        modifier = Modifier.size(48.dp).clearAndSetSemantics { }
                    )
                } else {
                    DownloadFileMenu(task, actions, busy, onShare, onOpenFile, onAction)
                }
            }
            if (task.state.isActive && task.state != DownloadState.Finalizing) {
                DownloadTransferDetails(task)
            }
            task.reason?.takeIf { task.state in setOf(DownloadState.Failed, DownloadState.Waiting) }?.let { reason ->
                Text(
                    reason,
                    modifier = Modifier.padding(top = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (task.state == DownloadState.Failed) colours.error else colours.onSurfaceVariant
                )
            }
            if (task.actualQuality != task.requestedQuality) {
                Text(
                    "所选清晰度不可用，使用可用版本",
                    modifier = Modifier.padding(top = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = colours.onSurfaceVariant
                )
            }
            FlowRow(
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalArrangement = Arrangement.spacedBy(4.dp),
                itemVerticalAlignment = Alignment.CenterVertically
            ) {
                DownloadCardStatus(task)
                if (!selecting) {
                    DownloadCardActions(task, actions, busy, onPlay, onAction)
                }
            }
        }
    }
}

@Composable
private fun DownloadCardHeader(task: DownloadTask, largeText: Boolean, trailing: @Composable () -> Unit) {
    val cover = task.selection?.let { selection ->
        selection.content.coverUrl?.takeIf { it.isNotBlank() } ?: selection.programme.coverUrl
    }
    val artwork: @Composable () -> Unit = {
        CoverImage(
            cover,
            Modifier.width(if (largeText) 104.dp else 88.dp).aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(8.dp)).testTag("download-cover-${task.id}")
        )
    }
    val details: @Composable () -> Unit = {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                task.title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = if (largeText) Int.MAX_VALUE else 3,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                "${task.programmeName} · ${task.broadcastDate} · ${task.actualQuality.label}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }

    if (largeText) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                artwork()
                Box(Modifier.size(48.dp)) { trailing() }
            }
            details()
        }
    } else {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            artwork()
            Box(Modifier.weight(1f)) { details() }
            Box(Modifier.size(48.dp)) { trailing() }
        }
    }
}

@Composable
private fun DownloadTransferDetails(task: DownloadTask) {
    val total = task.totalBytes?.takeIf { it > 0 }
    val colours = MaterialTheme.colorScheme
    val progressModifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(4.dp))

    Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (total != null) {
            LinearProgressIndicator(
                progress = { (task.bytes.toFloat() / total).coerceIn(0f, 1f) },
                modifier = progressModifier,
                gapSize = 0.dp,
                drawStopIndicator = {}
            )
        } else if (task.state != DownloadState.Paused) {
            LinearProgressIndicator(progressModifier)
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(downloadProgress(task), style = MaterialTheme.typography.bodySmall, color = colours.onSurfaceVariant)
            Text(
                if (task.wifiOnly) "仅 Wi-Fi 下载" else "允许蜂窝网络",
                style = MaterialTheme.typography.bodySmall,
                color = colours.onSurfaceVariant
            )
        }
        if (task.owner == DownloadOwner.LegacySystem) {
            Text(
                "系统下载任务不支持手动暂停",
                style = MaterialTheme.typography.bodySmall,
                color = colours.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun DownloadCardStatus(task: DownloadTask) {
    val colours = MaterialTheme.colorScheme
    val colour = when (task.state) {
        DownloadState.Failed -> colours.error
        DownloadState.Running, DownloadState.Completed -> colours.primary
        else -> colours.onSurfaceVariant
    }
    val icon = when (task.state) {
        DownloadState.Completed -> Icons.Outlined.CheckCircle
        DownloadState.Running -> Icons.Outlined.Download
        DownloadState.Paused -> Icons.Outlined.PauseCircle
        DownloadState.Failed -> Icons.Outlined.ErrorOutline
        DownloadState.Missing -> Icons.Outlined.FolderOff
        DownloadState.Cancelled -> Icons.Outlined.Cancel
        DownloadState.Finalizing -> Icons.Outlined.Save
        else -> Icons.Outlined.Schedule
    }

    FlowRow(
        modifier = Modifier.padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(16.dp), tint = colour)
            Spacer(Modifier.width(6.dp))
            Text(
                downloadStatus(task),
                modifier = Modifier.weight(1f, fill = false),
                style = MaterialTheme.typography.labelMedium,
                color = colour
            )
        }
        if (task.state == DownloadState.Completed) {
            Text(
                "· ${downloadSize(task)}",
                style = MaterialTheme.typography.bodySmall,
                color = colours.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun DownloadCardActions(
    task: DownloadTask,
    actions: Set<DownloadAction>,
    busy: Boolean,
    onPlay: (String) -> Unit,
    onAction: (DownloadAction) -> Unit
) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (task.state == DownloadState.Completed && task.contentUri != null) {
            TextButton(onClick = { onPlay(task.id) }, enabled = !busy) {
                Icon(Icons.Outlined.PlayArrow, null, Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("播放")
            }
        }
        DownloadAction.entries.filter {
            it in actions && it !in setOf(DownloadAction.DeleteFile, DownloadAction.RemoveRecord)
        }.forEach { action ->
            TextButton(onClick = { onAction(action) }, enabled = !busy) {
                val icon = when (action) {
                    DownloadAction.Pause -> Icons.Outlined.Pause
                    DownloadAction.Resume -> Icons.Outlined.PlayArrow
                    DownloadAction.Retry -> Icons.Outlined.Refresh
                    DownloadAction.Publish -> Icons.Outlined.Save
                    else -> null
                }
                icon?.let {
                    Icon(it, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                }
                Text(action.label)
            }
        }
    }
}

@Composable
private fun DownloadFileMenu(
    task: DownloadTask,
    actions: Set<DownloadAction>,
    busy: Boolean,
    onShare: (DownloadTask) -> Unit,
    onOpenFile: (DownloadTask) -> Unit,
    onAction: (DownloadAction) -> Unit
) {
    val fileActions = listOf(DownloadAction.DeleteFile, DownloadAction.RemoveRecord).filter { it in actions }
    var expanded by remember { mutableStateOf(false) }

    if (fileActions.isEmpty()) return

    Box {
        IconButton(onClick = { expanded = true }, enabled = !busy) { Icon(Icons.Outlined.MoreVert, "文件操作") }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            if (task.state == DownloadState.Completed && task.contentUri != null) {
                DropdownMenuItem(text = { Text("使用其他应用打开") }, onClick = {
                    expanded = false
                    onOpenFile(task)
                })
                DropdownMenuItem(text = { Text("分享视频") }, onClick = {
                    expanded = false
                    onShare(task)
                })
            }
            fileActions.forEach { action ->
                DropdownMenuItem(text = {
                    Text(
                        if (action == DownloadAction.RemoveRecord && task.state == DownloadState.Completed) {
                            "移除记录（保留文件）"
                        } else {
                            action.label
                        }
                    )
                }, onClick = {
                    expanded = false
                    onAction(action)
                })
            }
        }
    }
}
