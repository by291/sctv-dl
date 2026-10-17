package dev.sctvdl.feature.programmes.history.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.ui.media.CoverImage

@Composable
internal fun HistoryCard(entry: ViewingEntry, onOpen: () -> Unit, onRemove: () -> Unit) {
    val target = entry.target
    val title: String
    val context: String
    val cover: String?
    when (target) {
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
    Card(Modifier.fillMaxWidth()) {
        if (cover != null) CoverImage(cover, Modifier.fillMaxWidth().aspectRatio(16f / 9f))
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(
                context,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            val duration = entry.durationMs?.takeIf { it > 0 }
            if (duration != null) {
                LinearProgressIndicator(
                    progress = {
                        (entry.positionMs.toFloat() / duration).coerceIn(0f, 1f)
                    },
                    modifier = Modifier.fillMaxWidth()
                )
            }
            Text(
                if (entry.completed) "已看完" else "看到 ${timeLabel(entry.positionMs)}",
                style = MaterialTheme.typography.bodySmall
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onOpen) { Text(if (entry.completed) "重新播放" else "继续播放") }
                TextButton(onClick = onRemove) { Text("移除记录") }
            }
        }
    }
}

private fun timeLabel(ms: Long): String {
    val seconds = ms.coerceAtLeast(0) / 1000
    return if (seconds >= 3600) {
        "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60)
    } else {
        "%d:%02d".format(seconds / 60, seconds % 60)
    }
}
