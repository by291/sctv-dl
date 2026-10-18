package dev.sctvdl.feature.programmes.catalogue.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.platform.ViewConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.ui.media.CoverImage
import dev.sctvdl.ui.programme.LocalProgrammeCoverTransitionState
import dev.sctvdl.ui.programme.sharedProgrammeCover

@Composable
internal fun ProgrammeCard(
    programme: Programme,
    favourite: Boolean,
    onOpen: () -> Unit,
    onFavourite: () -> Unit,
    shareCover: Boolean = false
) {
    val colours = MaterialTheme.colorScheme
    val typography = MaterialTheme.typography
    val coverTransition = LocalProgrammeCoverTransitionState.current
    val viewConfiguration = LocalViewConfiguration.current
    val favouriteConfiguration = remember(viewConfiguration) {
        object : ViewConfiguration by viewConfiguration {
            override val minimumTouchTargetSize = DpSize(32.dp, 32.dp)
        }
    }
    val coverShape = RoundedCornerShape(
        topStart = MaterialTheme.shapes.large.topStart,
        topEnd = MaterialTheme.shapes.large.topEnd,
        bottomStart = CornerSize(0.dp),
        bottomEnd = CornerSize(0.dp)
    )
    val coverModifier = if (shareCover) Modifier.sharedProgrammeCover(programme, coverShape) else Modifier
    Card(
        onClick = {
            coverTransition?.select(programme)
            onOpen()
        },
        modifier = Modifier.testTag("programme-${programme.id}"),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = colours.surfaceContainerLow),

        border = BorderStroke(1.dp, colours.outlineVariant.copy(alpha = 0.5f))
    ) {
        Box {
            CoverImage(programme.coverUrl, coverModifier.fillMaxWidth().aspectRatio(16f / 9f).clip(coverShape))
            CompositionLocalProvider(
                LocalMinimumInteractiveComponentSize provides 0.dp,
                LocalViewConfiguration provides favouriteConfiguration
            ) {
                FilledTonalIconButton(
                    onClick = onFavourite,
                    modifier = Modifier.align(Alignment.TopEnd).padding(8.dp).size(32.dp),
                    colors = IconButtonDefaults.filledTonalIconButtonColors(
                        containerColor = colours.surface.copy(alpha = 0.94f)
                    )
                ) {
                    Icon(
                        if (favourite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                        "${if (favourite) "取消收藏" else "收藏"}${programme.name}",
                        modifier = Modifier.size(20.dp),
                        tint = if (favourite) colours.primary else colours.onSurfaceVariant
                    )
                }
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
