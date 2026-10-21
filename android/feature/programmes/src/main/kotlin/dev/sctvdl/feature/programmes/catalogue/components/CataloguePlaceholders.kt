package dev.sctvdl.feature.programmes.catalogue.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.SkeletonBlock
import dev.sctvdl.design.components.SkeletonContent
import dev.sctvdl.design.theme.TouchTarget

@Composable
internal fun ProgrammeSpotlightPlaceholder() {
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val typography = MaterialTheme.typography
    val labelSize = with(LocalDensity.current) { typography.labelLarge.fontSize.toDp() }
    val labelHeight = with(LocalDensity.current) { typography.labelLarge.lineHeight.toDp() }
    val titleHeight = with(LocalDensity.current) { typography.titleLarge.lineHeight.toDp() }
    val bodyHeight = with(LocalDensity.current) { typography.bodyMedium.lineHeight.toDp() }
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f),
        shape = MaterialTheme.shapes.large,
        modifier = Modifier.fillMaxWidth().testTag("spotlight-placeholder")
    ) {
        SkeletonContent(Modifier.padding(16.dp)) {
            BoxWithConstraints {
                val availableWidth = maxWidth
                val wide = availableWidth >= 480.dp && !largeText
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            SkeletonBlock(Modifier.width(labelSize * 4).height(labelHeight))
                            SkeletonBlock(Modifier.fillMaxWidth(0.8f).height(titleHeight))
                            if (wide) SkeletonBlock(Modifier.fillMaxWidth(0.9f).height(bodyHeight))
                        }
                        if (!largeText) {
                            SpotlightCoverFrame(availableWidth) { modifier -> SkeletonBlock(modifier) }
                        }
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SkeletonBlock(
                            Modifier.width(labelSize * 4 + 52.dp).height(maxOf(TouchTarget, labelHeight + 8.dp))
                        )
                        SkeletonBlock(
                            Modifier.width(labelSize * 3 + 48.dp).height(maxOf(TouchTarget, labelHeight + 8.dp))
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun CatalogueSummaryPlaceholder() {
    SkeletonContent {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SkeletonBlock(Modifier.width(88.dp).height(20.dp)) }
            SkeletonBlock(Modifier.width(112.dp).height(TouchTarget))
        }
    }
}

@Composable
internal fun ProgrammeCardPlaceholder(index: Int) {
    val typography = MaterialTheme.typography
    val titleHeight = with(LocalDensity.current) { typography.titleMedium.lineHeight.toDp() }
    Card(
        modifier = Modifier.fillMaxWidth().testTag("programme-placeholder-$index"),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
    ) {
        SkeletonContent {
            Column {
                SkeletonBlock(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(MaterialTheme.shapes.large))
                Box(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                    SkeletonBlock(Modifier.fillMaxWidth(0.8f).height(titleHeight))
                }
            }
        }
    }
}
