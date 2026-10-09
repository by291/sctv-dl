package dev.sctvdl.design

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.Programme

@Composable
fun ProgrammeCard(programme: Programme, favourite: Boolean, onOpen: () -> Unit, onFavourite: () -> Unit) {
    val colours = MaterialTheme.colorScheme
    val typography = MaterialTheme.typography
    Card(
        onClick = onOpen,
        modifier = Modifier.testTag("programme-${programme.id}"),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = colours.surfaceContainerLow),

        border = BorderStroke(1.dp, colours.outlineVariant.copy(alpha = 0.5f))
    ) {
        Box {
            CoverImage(programme.coverUrl, Modifier.fillMaxWidth().aspectRatio(16f / 9f))
            FilledTonalIconButton(
                onClick = onFavourite,
                modifier = Modifier.align(Alignment.TopEnd).padding(4.dp),
                colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = colours.surface.copy(alpha = 0.94f)
                )
            ) {
                Icon(
                    if (favourite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                    "${if (favourite) "取消收藏" else "收藏"}${programme.name}",
                    tint = if (favourite) colours.primary else colours.onSurfaceVariant
                )
            }
        }
        Text(
            programme.name,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            style = typography.titleMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
    }
}
