package dev.sctvdl.feature.programmes.history.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MoreVert
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Replay
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.ui.media.CoverImage
import java.util.Locale

@Composable
internal fun HistoryCard(entry: ViewingEntry, onOpen: () -> Unit, onRemove: () -> Unit) {
    val title: String
    val context: String
    val cover: String?
    when (val target = entry.target) {
        is ViewingTarget.Online -> {
            title = target.selection.content.title
            context = "${target.selection.programme.name} · ${target.selection.broadcast.date}"
            cover = target.selection.content.coverUrl ?: target.selection.programme.coverUrl
        }
        is ViewingTarget.LegacyDownload -> {
            title = target.title
            context = "${target.programmeName} · ${target.broadcastDate} · 本地视频"
            cover = null
        }
    }
    val duration = entry.durationMs?.takeIf { it > 0 }
    val started = entry.positionMs > 0
    val progress = if (!entry.completed && started && duration != null) {
        (entry.positionMs.toFloat() / duration).coerceIn(0f, 1f)
    } else {
        null
    }
    val status = when {
        entry.completed -> "已看完"
        !started -> "尚未播放"
        else -> "看到 ${timeLabel(entry.positionMs)}" + (duration?.let { " / ${timeLabel(it)}" } ?: "")
    }
    val action = when {
        entry.completed -> "再看一次"
        started -> "继续观看"
        else -> "播放"
    }
    val largeText = LocalDensity.current.fontScale >= 1.5f

    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Card(
            Modifier.widthIn(max = 720.dp).fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = .5f))
        ) {
            BoxWithConstraints {
                val availableWidth = maxWidth
                val stacked = largeText && availableWidth < 480.dp
                val coverWidth = if (availableWidth < 340.dp) 88.dp else 104.dp
                Column {
                    Box(
                        Modifier.fillMaxWidth().clickable(
                            onClickLabel = "播放节目：$title",
                            role = Role.Button,
                            onClick = onOpen
                        ).padding(start = 12.dp, top = 14.dp, end = 12.dp)
                    ) {
                        if (stacked) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                HistoryArtwork(cover, coverWidth, progress)
                                HistoryDetails(title, context, largeText)
                            }
                        } else {
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                HistoryArtwork(cover, coverWidth, progress)
                                HistoryDetails(title, context, largeText, Modifier.weight(1f))
                            }
                        }
                    }
                    if (stacked || availableWidth < 300.dp) {
                        Column(Modifier.fillMaxWidth().padding(start = 12.dp, top = 10.dp, end = 4.dp, bottom = 6.dp)) {
                            HistoryStatus(status)
                            HistoryActions(entry.completed, action, onOpen, onRemove, Modifier.align(Alignment.End))
                        }
                    } else {
                        Row(
                            Modifier.fillMaxWidth().padding(start = 12.dp, top = 4.dp, end = 4.dp, bottom = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            HistoryStatus(status, Modifier.weight(1f))
                            Spacer(Modifier.width(4.dp))
                            HistoryActions(entry.completed, action, onOpen, onRemove)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryArtwork(url: String?, width: Dp, progress: Float?) {
    Box(Modifier.width(width).aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)).testTag("history-cover")) {
        CoverImage(url, Modifier.fillMaxSize())
        if (progress != null) {
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(3.dp)
                    .semantics { contentDescription = "观看进度" },
                trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                strokeCap = StrokeCap.Butt,
                gapSize = 0.dp,
                drawStopIndicator = {}
            )
        }
    }
}

@Composable
private fun HistoryDetails(title: String, context: String, largeText: Boolean, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            maxLines = if (largeText) Int.MAX_VALUE else 2,
            overflow = TextOverflow.Ellipsis
        )
        HistoryStatus(context)
    }
}

@Composable
private fun HistoryStatus(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun HistoryActions(
    completed: Boolean,
    action: String,
    onOpen: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    var menu by remember { mutableStateOf(false) }
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onOpen) {
            Icon(if (completed) Icons.Outlined.Replay else Icons.Outlined.PlayArrow, null, Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
            Text(action)
        }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Outlined.MoreVert, "更多操作", Modifier.size(20.dp)) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("移除观看记录") }, onClick = {
                    menu = false
                    onRemove()
                })
            }
        }
    }
}

private fun timeLabel(ms: Long): String {
    val seconds = ms.coerceAtLeast(0) / 1000
    return if (seconds >= 3600) {
        String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    } else {
        String.format(Locale.ROOT, "%d:%02d", seconds / 60, seconds % 60)
    }
}
