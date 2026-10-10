package dev.sctvdl.design.components

import android.animation.ValueAnimator
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.valentinilk.shimmer.shimmer

@Composable
fun SkeletonContent(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier.then(if (ValueAnimator.areAnimatorsEnabled()) Modifier.shimmer() else Modifier)
            .clearAndSetSemantics { }
    ) { content() }
}

@Composable
fun SkeletonBlock(modifier: Modifier) {
    Box(modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest, MaterialTheme.shapes.small))
}
