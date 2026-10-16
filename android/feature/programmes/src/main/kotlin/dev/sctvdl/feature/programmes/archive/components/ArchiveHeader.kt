package dev.sctvdl.feature.programmes.archive.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.theme.TouchTarget
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.feature.programmes.archive.ArchiveUiState
import dev.sctvdl.ui.media.CoverImage
import dev.sctvdl.ui.programme.sharedProgrammeCover
import java.time.format.DateTimeFormatter
import java.util.Locale

private val RecentDateLabel = DateTimeFormatter.ofPattern("M月d日", Locale.SIMPLIFIED_CHINESE)
private val WeekdayLabel = DateTimeFormatter.ofPattern("EEE", Locale.SIMPLIFIED_CHINESE)

@Composable
internal fun ArchiveHeader(state: ArchiveUiState, onFavourite: () -> Unit) {
    ArchiveHeaderLayout(
        cover = { modifier ->
            val sharedCover = state.programme?.let {
                Modifier.sharedProgrammeCover(it, MaterialTheme.shapes.medium)
            } ?: Modifier
            CoverImage(state.programme?.coverUrl, sharedCover.then(modifier).clip(MaterialTheme.shapes.medium))
        },
        details = {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    state.programme?.name ?: "往期节目",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold
                )
                TextButton(
                    onClick = onFavourite,
                    enabled = state.programmeId.isNotBlank(),
                    contentPadding = PaddingValues(horizontal = 0.dp),
                    modifier = Modifier.heightIn(min = TouchTarget)
                ) {
                    Icon(
                        if (state.favourite) Icons.Filled.Favorite else Icons.Outlined.FavoriteBorder,
                        null,
                        Modifier.size(18.dp)
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(if (state.favourite) "已收藏" else "收藏栏目")
                }
            }
        }
    )
}

@Composable
internal fun ArchiveHeaderLayout(cover: @Composable (Modifier) -> Unit, details: @Composable () -> Unit) {
    val largeText = LocalDensity.current.fontScale >= 1.5f

    BoxWithConstraints(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (largeText) {
            details()
        } else {
            val compact = maxWidth < 348.dp
            val gap = if (compact) 12.dp else 16.dp
            val coverWidth = ((maxWidth - gap) * if (compact) 0.52f else 0.54f).coerceAtMost(256.dp)
            Row(
                horizontalArrangement = Arrangement.spacedBy(gap),
                verticalAlignment = Alignment.CenterVertically
            ) {
                cover(Modifier.width(coverWidth).aspectRatio(16f / 9f))
                Box(Modifier.weight(1f)) { details() }
            }
        }
    }
}

@Composable
internal fun BroadcastDates(
    dates: List<BroadcastDate>,
    selected: BroadcastDate?,
    onDate: (BroadcastDate) -> Unit,
    onMore: () -> Unit
) {
    // Keep a date chosen from the full sheet visible even when it is outside the recent broadcasts.
    val recent = (dates.sortedByDescending { it.date }.take(7) + listOfNotNull(selected))
        .distinctBy { it.id }.sortedByDescending { it.date }
    val scroll = rememberLazyListState()
    LaunchedEffect(selected?.id) {
        val index = recent.indexOfFirst { it.id == selected?.id }
        if (index >= 0) scroll.animateScrollToItem(index)
    }

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("播出日期", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
            TextButton(onClick = onMore) {
                Icon(Icons.Outlined.CalendarMonth, null, Modifier.size(18.dp))
                Text("更多日期", Modifier.padding(start = 6.dp))
            }
        }
        LazyRow(
            state = scroll,
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(recent, key = { it.id }) { date ->
                FilterChip(
                    selected = date.id == selected?.id,
                    onClick = { if (date.id != selected?.id) onDate(date) },
                    label = {
                        Column(Modifier.padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(date.date.format(RecentDateLabel))
                            Text(date.date.format(WeekdayLabel), style = MaterialTheme.typography.labelSmall)
                        }
                    },
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.heightIn(min = TouchTarget).semantics { contentDescription = "回看${date.date}" }
                )
            }
        }
    }
}
