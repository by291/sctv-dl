package dev.sctvdl.design

import android.animation.ValueAnimator
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.valentinilk.shimmer.shimmer

@Composable
fun ProgrammeSpotlightPlaceholder() {
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
                val wide = maxWidth >= 480.dp && !largeText
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
                            SkeletonBlock(Modifier.width(if (wide) 160.dp else 88.dp).aspectRatio(16f / 9f))
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
fun CatalogueSummaryPlaceholder() {
    SkeletonContent {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { SkeletonBlock(Modifier.width(88.dp).height(20.dp)) }
            SkeletonBlock(Modifier.width(112.dp).height(TouchTarget))
        }
    }
}

@Composable
fun ProgrammeCardPlaceholder(index: Int) {
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
                SkeletonBlock(Modifier.fillMaxWidth().aspectRatio(16f / 9f))
                Box(Modifier.padding(horizontal = 12.dp, vertical = 10.dp)) {
                    SkeletonBlock(Modifier.fillMaxWidth(0.8f).height(titleHeight))
                }
            }
        }
    }
}

@Composable
fun ArchiveHeaderPlaceholder() {
    val titleHeight = with(LocalDensity.current) { MaterialTheme.typography.titleLarge.lineHeight.toDp() }
    val bodyHeight = with(LocalDensity.current) { MaterialTheme.typography.bodyMedium.lineHeight.toDp() }
    SkeletonContent(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (LocalDensity.current.fontScale < 1.5f) {
                SkeletonBlock(Modifier.width(112.dp).aspectRatio(4f / 3f))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SkeletonBlock(Modifier.fillMaxWidth(0.75f).height(titleHeight))
                SkeletonBlock(Modifier.fillMaxWidth(0.4f).height(bodyHeight))
            }
        }
    }
}

@Composable
fun BroadcastDatesPlaceholder() {
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
fun ArchiveContentPlaceholder() {
    val largeText = LocalDensity.current.fontScale >= 1.5f
    val titleHeight = with(LocalDensity.current) { MaterialTheme.typography.titleMedium.lineHeight.toDp() }
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
                SkeletonBlock(Modifier.width(120.dp).height(titleHeight))
                repeat(3) {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)
                    ) {
                        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            if (!largeText) SkeletonBlock(Modifier.width(88.dp).aspectRatio(4f / 3f))
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                SkeletonBlock(Modifier.fillMaxWidth().height(titleHeight))
                                SkeletonBlock(Modifier.fillMaxWidth(0.7f).height(titleHeight))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SkeletonContent(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier.then(if (ValueAnimator.areAnimatorsEnabled()) Modifier.shimmer() else Modifier)
            .clearAndSetSemantics { }
    ) { content() }
}

@Composable
private fun SkeletonBlock(modifier: Modifier) {
    Box(modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest, MaterialTheme.shapes.small))
}
