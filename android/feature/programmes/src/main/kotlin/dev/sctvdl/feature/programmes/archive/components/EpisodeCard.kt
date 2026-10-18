package dev.sctvdl.feature.programmes.archive.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.theme.TouchTarget
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.ContentRef
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.feature.programmes.archive.clipPublicationLabel
import dev.sctvdl.ui.programme.PlaybackCover
import java.time.LocalDate

@Composable
internal fun EpisodeCard(
    content: ProgrammeContent,
    fullEpisode: Boolean,
    selectionMode: Boolean,
    selected: Boolean,
    onPlay: () -> Unit,
    onSelect: () -> Unit,
    broadcastDate: LocalDate? = null,
    playbackReference: ContentRef? = null,
    programmeCoverUrl: String? = null
) {
    val colours = MaterialTheme.colorScheme
    val playable = videoVariants(content).isNotEmpty()
    val containerColor = if (selectionMode && selected) colours.primaryContainer else colours.surfaceContainerLow
    val border = BorderStroke(
        if (selected) 2.dp else 1.dp,
        if (selected) colours.primary else colours.outlineVariant.copy(alpha = 0.5f)
    )
    val cardModifier = Modifier.fillMaxWidth().heightIn(min = TouchTarget).testTag("content-${content.id}")
        .semantics {
            if (selectionMode) {
                role = Role.Checkbox
                contentDescription = "${if (selected) "取消选择" else "选择"}${content.title}"
            } else {
                role = Role.Button
                contentDescription = "播放节目：${content.title}"
                onClick(label = "进入播放页", action = null)
            }
        }
    val cardContent: @Composable () -> Unit = {
        EpisodeCardBody(
            content = content,
            fullEpisode = fullEpisode,
            selectionMode = selectionMode,
            selected = selected,
            playable = playable,
            broadcastDate = broadcastDate,
            playbackReference = if (playable && !selectionMode) playbackReference else null,
            programmeCoverUrl = programmeCoverUrl
        )
    }

    // Material's interactive surfaces keep the indication inside the same shape that clips the card content.
    if (selectionMode) {
        Surface(
            checked = selected,
            onCheckedChange = { onSelect() },
            enabled = playable,
            modifier = cardModifier,
            shape = MaterialTheme.shapes.medium,
            color = containerColor,
            border = border,
            content = cardContent
        )
    } else {
        Surface(
            onClick = onPlay,
            enabled = playable,
            modifier = cardModifier,
            shape = MaterialTheme.shapes.medium,
            color = containerColor,
            border = border,
            content = cardContent
        )
    }
}

@Composable
private fun EpisodeCardBody(
    content: ProgrammeContent,
    fullEpisode: Boolean,
    selectionMode: Boolean,
    selected: Boolean,
    playable: Boolean,
    broadcastDate: LocalDate?,
    playbackReference: ContentRef?,
    programmeCoverUrl: String?
) {
    val colours = MaterialTheme.colorScheme
    val typography = MaterialTheme.typography
    val largeText = LocalDensity.current.fontScale >= 1.5f

    Column {
        if (fullEpisode && !selectionMode) {
            ContentPreview(content, true, playable, Modifier.fillMaxWidth(), playbackReference, programmeCoverUrl)
        }
        Row(
            Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (selectionMode) {
                Checkbox(
                    checked = selected,
                    onCheckedChange = null,
                    enabled = playable,
                    modifier = Modifier.clearAndSetSemantics { }
                )
            }
            if (!largeText && (!fullEpisode || selectionMode)) {
                ContentPreview(
                    content,
                    false,
                    playable && !selectionMode,
                    Modifier.width(if (selectionMode) 64.dp else 104.dp),
                    playbackReference,
                    programmeCoverUrl
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (fullEpisode) {
                    Text("完整节目", style = typography.labelLarge, color = colours.primary)
                }
                Text(
                    content.title,
                    style = if (fullEpisode && !selectionMode) typography.titleLarge else typography.titleMedium,
                    maxLines = if (largeText) 6 else 2,
                    overflow = TextOverflow.Ellipsis
                )
                if (!fullEpisode) {
                    Text(
                        clipPublicationLabel(content, broadcastDate),
                        style = typography.bodySmall,
                        color = colours.onSurfaceVariant
                    )
                }
                if (!playable) {
                    Text("暂未提供视频", style = typography.bodySmall, color = colours.onSurfaceVariant)
                }
            }
            if (largeText && !selectionMode && !fullEpisode && playable) {
                Icon(Icons.Outlined.PlayArrow, null, Modifier.size(24.dp), tint = colours.primary)
            }
        }
    }
}

@Composable
private fun ContentPreview(
    content: ProgrammeContent,
    fullEpisode: Boolean,
    showPlay: Boolean,
    modifier: Modifier,
    playbackReference: ContentRef?,
    programmeCoverUrl: String?
) {
    Box(modifier.aspectRatio(if (fullEpisode) 16f / 9f else 4f / 3f)) {
        PlaybackCover(
            playbackReference,
            content.coverUrl ?: programmeCoverUrl,
            Modifier.matchParentSize(),
            cornerRadius = if (fullEpisode) 12.dp else 8.dp
        )
        if (showPlay) {
            Surface(
                modifier = Modifier.align(Alignment.BottomEnd).padding(if (fullEpisode) 12.dp else 6.dp)
                    .size(if (fullEpisode) 40.dp else 28.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
                contentColor = MaterialTheme.colorScheme.primary
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.PlayArrow, null, Modifier.size(if (fullEpisode) 24.dp else 18.dp))
                }
            }
        }
    }
}
