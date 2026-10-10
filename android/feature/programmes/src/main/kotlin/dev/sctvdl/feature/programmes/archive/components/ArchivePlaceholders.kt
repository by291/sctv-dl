package dev.sctvdl.feature.programmes.archive.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.SkeletonBlock
import dev.sctvdl.design.components.SkeletonContent
import dev.sctvdl.design.theme.TouchTarget

@Composable
internal fun ArchiveHeaderPlaceholder() {
    val typography = MaterialTheme.typography
    val titleHeight = with(LocalDensity.current) { typography.titleLarge.lineHeight.toDp() }
    val labelHeight = with(LocalDensity.current) { typography.labelLarge.lineHeight.toDp() }
    val labelSize = with(LocalDensity.current) { typography.labelLarge.fontSize.toDp() }
    SkeletonContent(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            if (LocalDensity.current.fontScale < 1.5f) {
                SkeletonBlock(Modifier.width(144.dp).aspectRatio(16f / 9f))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SkeletonBlock(Modifier.fillMaxWidth(0.75f).height(titleHeight))
                SkeletonBlock(Modifier.width(labelSize * 4 + 24.dp).height(maxOf(TouchTarget, labelHeight)))
            }
        }
    }
}

@Composable
internal fun BroadcastDatesPlaceholder() {
    val labelHeight = with(LocalDensity.current) { MaterialTheme.typography.labelLarge.lineHeight.toDp() }
    Box(Modifier.testTag("archive-dates-placeholder")) {
        SkeletonContent(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(3) { SkeletonBlock(Modifier.weight(1f).height(maxOf(TouchTarget, labelHeight + 16.dp))) }
            }
        }
    }
}

@Composable
internal fun ArchiveContentPlaceholder() {
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val titleHeight = with(LocalDensity.current) { MaterialTheme.typography.titleMedium.lineHeight.toDp() }
    val timeHeight = with(LocalDensity.current) { MaterialTheme.typography.bodySmall.lineHeight.toDp() }
    Box(Modifier.fillMaxWidth().testTag("archive-content-placeholder")) {
        SkeletonContent(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    SkeletonBlock(Modifier.fillMaxWidth(0.65f).height(titleHeight))
                    SkeletonBlock(Modifier.fillMaxWidth(0.5f).height(20.dp))
                }
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                    Column {
                        SkeletonBlock(Modifier.fillMaxWidth().aspectRatio(16f / 9f))
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            SkeletonBlock(Modifier.width(80.dp).height(20.dp))
                            SkeletonBlock(Modifier.fillMaxWidth(0.85f).height(titleHeight * 2))
                        }
                    }
                }
                Row(
                    Modifier.fillMaxWidth().height(maxOf(TouchTarget, titleHeight)),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SkeletonBlock(Modifier.width(120.dp).height(titleHeight))
                    SkeletonBlock(Modifier.width(24.dp).height(24.dp))
                }
                repeat(3) {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
                    ) {
                        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            if (!largeText) SkeletonBlock(Modifier.width(104.dp).aspectRatio(4f / 3f))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                SkeletonBlock(Modifier.fillMaxWidth().height(titleHeight))
                                SkeletonBlock(Modifier.fillMaxWidth(0.7f).height(titleHeight))
                                SkeletonBlock(Modifier.width(64.dp).height(timeHeight))
                            }
                        }
                    }
                }
            }
        }
    }
}
