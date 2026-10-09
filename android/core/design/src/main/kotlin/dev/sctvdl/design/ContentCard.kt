package dev.sctvdl.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
    onSelect: () -> Unit
) {
    val colours = MaterialTheme.colorScheme
    val typography = MaterialTheme.typography
    val playable = videoVariants(content).isNotEmpty()
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val interaction = if (selectionMode) {
        Modifier.toggleable(selected, enabled = playable, role = Role.Checkbox, onValueChange = { onSelect() })
            .semantics { contentDescription = "${if (selected) "取消选择" else "选择"}${content.title}" }
    } else {
        Modifier.clickable(
            enabled = playable,
            role = Role.Button,
            onClickLabel = "进入播放页",
            onClick = onPlay
        ).semantics { contentDescription = "播放节目：${content.title}" }
    }

    Card(
        modifier = Modifier.fillMaxWidth().heightIn(min = TouchTarget).testTag("content-${content.id}")
            .then(interaction),
        colors = CardDefaults.cardColors(
            containerColor = if (selectionMode && selected) colours.primaryContainer else colours.surfaceContainerLow
        ),
        border = BorderStroke(
            if (selected) 2.dp else 1.dp,
            if (selected) colours.primary else colours.outlineVariant.copy(alpha = 0.5f)
        )
    ) {
        if (fullEpisode && !selectionMode) {
            ContentPreview(content, true, playable, Modifier.fillMaxWidth())
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
                    Modifier.width(if (selectionMode) 64.dp else 104.dp)
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (fullEpisode) {
                    Text("完整节目", style = typography.labelLarge, color = colours.primary)
                }
                Text(
                    content.title,
                    style = if (fullEpisode && !selectionMode) typography.titleLarge else typography.titleMedium,
                    maxLines = if (largeText) 6 else 3,
                    overflow = TextOverflow.Ellipsis
                )
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
private fun ContentPreview(content: ProgrammeContent, fullEpisode: Boolean, showPlay: Boolean, modifier: Modifier) {
    Box(modifier.aspectRatio(if (fullEpisode) 16f / 9f else 4f / 3f)) {
        CoverImage(
            content.coverUrl,
            Modifier.matchParentSize().clip(
                if (fullEpisode) MaterialTheme.shapes.medium else MaterialTheme.shapes.small
            )
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
