package dev.sctvdl.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.videoVariants

@Composable
fun ContentCard(
    content: ProgrammeContent,
    fullEpisode: Boolean,
    selectionMode: Boolean,
    selected: Boolean,
    onPlay: () -> Unit,
    onDownload: () -> Unit,
    onSelect: () -> Unit
) {
    val colours = MaterialTheme.colorScheme
    val typography = MaterialTheme.typography
    val playable = videoVariants(content).isNotEmpty()
    val largeText = LocalDensity.current.fontScale >= 1.5f
    Card(
        colors = CardDefaults.cardColors(containerColor = colours.surfaceContainerLow),

        border = BorderStroke(
            if (selected) 2.dp else 1.dp,
            if (selected) {
                colours.primary
            } else {
                colours.outlineVariant.copy(alpha = 0.5f)
            }
        )
    ) {
        if (fullEpisode) CoverImage(content.coverUrl, Modifier.fillMaxWidth().aspectRatio(16f / 9f))
        Row(
            Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            if (!fullEpisode && !largeText) {
                CoverImage(
                    content.coverUrl,
                    Modifier.width(92.dp).aspectRatio(4f / 3f)
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (fullEpisode) {
                    Text(
                        "完整节目",
                        style = typography.labelLarge,
                        color = colours.primary
                    )
                }
                Text(
                    content.title,
                    style = if (fullEpisode) typography.titleLarge else typography.titleMedium,
                    maxLines = if (largeText) 6 else 3,
                    overflow = TextOverflow.Ellipsis
                )
                if (!playable) {
                    Text(
                        "暂未提供视频",
                        style = typography.bodySmall,
                        color = colours.onSurfaceVariant
                    )
                }
                if (selectionMode) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = selected,
                            onCheckedChange = { onSelect() },
                            enabled = playable,
                            modifier = Modifier.semantics {
                                contentDescription = "${if (selected) "取消选择" else "选择"}${content.title}"
                            }
                        )
                        Text(
                            if (selected) "已选择" else "选择节目",
                            style = typography.labelLarge
                        )
                    }
                } else {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilledTonalButton(
                            onClick = onPlay,
                            enabled = playable,
                            contentPadding = PaddingValues(horizontal = 12.dp),
                            modifier = Modifier.heightIn(min = TouchTarget)
                        ) {
                            Icon(Icons.Outlined.PlayArrow, null, Modifier.size(20.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("播放")
                        }
                        TextButton(
                            onClick = onDownload,
                            enabled = playable,
                            contentPadding = PaddingValues(horizontal = 12.dp),
                            modifier = Modifier.heightIn(min = TouchTarget)
                        ) {
                            Icon(Icons.Outlined.Download, null, Modifier.size(20.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("下载")
                        }
                    }
                }
            }
        }
    }
}
