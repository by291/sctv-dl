package dev.sctvdl.ui.programme

import androidx.compose.animation.EnterExitState
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.theme.PAGE_TRANSITION_DURATION_MILLIS
import dev.sctvdl.domain.programme.ContentRef
import dev.sctvdl.ui.media.CoverImage
import kotlin.math.abs

private data class PlaybackCoverKey(val reference: ContentRef, val url: String)

/**
 * Shares artwork only; the video surface stays in its final bounds underneath.
 * A null [videoReady] identifies an archive cover. A player keeps this composable
 * mounted after its first frame so a return can reveal the archive cover gradually.
 */
@Composable
fun PlaybackCover(
    reference: ContentRef?,
    url: String?,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 0.dp,
    videoReady: Boolean? = null
) {
    val sharedScope = LocalProgrammeCoverSharedScope.current
    val animationScope = LocalProgrammeCoverAnimationScope.current
    val transition = animationScope?.transition
    val inPlayer = videoReady != null
    var entered by remember(url) { mutableStateOf(transition == null) }
    var fullyVisible by rememberSaveable(reference, url) { mutableStateOf(false) }

    LaunchedEffect(url, transition?.currentState, transition?.targetState, transition?.isRunning) {
        if (transition == null || (
                transition.currentState == EnterExitState.Visible &&
                    transition.targetState == EnterExitState.Visible && !transition.isRunning
                )
        ) {
            entered = true
        }
    }
    // Do not expose an early decoded frame in the middle of the cover's flight.
    val opacity by animateFloatAsState(
        if (videoReady == true && entered) 0f else 1f,
        tween(120),
        label = "Playback artwork"
    )
    val sharedModifier = if (sharedScope != null && animationScope != null && reference != null && url != null) {
        with(sharedScope) {
            val config = remember(inPlayer, reference, url) {
                object : SharedTransitionScope.SharedContentConfig {
                    override val SharedTransitionScope.SharedContentState.isEnabled: Boolean
                        get() = inPlayer || fullyVisible
                }
            }
            val sharedContent = rememberSharedContentState(PlaybackCoverKey(reference, url), config)
            Modifier.sharedBounds(
                sharedContent,
                animatedVisibilityScope = animationScope,
                // On return, artwork complements the departing video instead of flashing over it.
                enter = if (inPlayer) {
                    EnterTransition.None
                } else {
                    fadeIn(tween((PAGE_TRANSITION_DURATION_MILLIS * 0.35f).toInt(), easing = FastOutLinearInEasing))
                },
                exit = ExitTransition.None,
                resizeMode = SharedTransitionScope.ResizeMode.RemeasureToBounds,
                boundsTransform = { _, _ -> tween(PAGE_TRANSITION_DURATION_MILLIS, easing = FastOutSlowInEasing) }
            )
        }
    } else {
        Modifier
    }

    CoverImage(
        url,
        modifier.onGloballyPositioned { coordinates ->
            // A clipped list image must not escape its viewport into the shared overlay.
            // Freeze the eligibility through a flight, and retain it while the archive is parked.
            if (!inPlayer && sharedScope?.isTransitionActive != true &&
                (
                    transition == null || (
                        transition.currentState == EnterExitState.Visible &&
                            transition.targetState == EnterExitState.Visible
                        )
                    )
            ) {
                val clipped = coordinates.boundsInWindow()
                val full = coordinates.boundsInWindow(clipBounds = false)
                fullyVisible = full.width > 0 && full.height > 0 &&
                    abs(clipped.width - full.width) < 1f && abs(clipped.height - full.height) < 1f
            }
        }.then(sharedModifier).graphicsLayer { alpha = opacity }.clip(RoundedCornerShape(cornerRadius))
    )
}
