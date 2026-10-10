package dev.sctvdl.design

import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.toSize
import dev.sctvdl.domain.Programme

val LocalProgrammeCoverSharedScope = compositionLocalOf<SharedTransitionScope?> { null }
val LocalProgrammeCoverAnimationScope = compositionLocalOf<AnimatedVisibilityScope?> { null }
val LocalProgrammeCoverTransitionState = compositionLocalOf<ProgrammeCoverTransitionState?> { null }

private data class ProgrammeCoverKey(val programmeId: String, val url: String)
private data class ProgrammeCoverSource(val key: ProgrammeCoverKey, val rotation: Float)

private class ProgrammeCoverMotion(initialRotation: Float) {
    var initialBounds: Rect? = null
    var targetBounds: Rect? = null
    var initialRotation = initialRotation
    var targetRotation = initialRotation
    var rotation by mutableFloatStateOf(initialRotation)

    fun update(bounds: Rect) {
        val initial = initialBounds ?: return
        val target = targetBounds ?: return
        val distance = target.center - initial.center
        val sizeDifference = Offset(target.width - initial.width, target.height - initial.height)
        val travelled = bounds.center - initial.center
        val resized = Offset(bounds.width - initial.width, bounds.height - initial.height)
        val total = distance.getDistanceSquared() + sizeDifference.getDistanceSquared()
        val completed = travelled.x * distance.x + travelled.y * distance.y +
            resized.x * sizeDifference.x + resized.y * sizeDifference.y
        val progress = if (total == 0f) 1f else (completed / total).coerceIn(0f, 1f)

        rotation = initialRotation + (targetRotation - initialRotation) * progress
    }
}

class ProgrammeCoverTransitionState {
    private var source by mutableStateOf<ProgrammeCoverSource?>(null)

    internal fun select(programme: Programme, rotation: Float = 0f) {
        source = programme.coverUrl?.let { ProgrammeCoverSource(ProgrammeCoverKey(programme.id, it), rotation) }
    }

    internal fun sourceRotation(programme: Programme): Float = source?.takeIf {
        it.key == ProgrammeCoverKey(programme.id, programme.coverUrl.orEmpty())
    }?.rotation ?: 0f
}

@Composable
fun Modifier.sharedProgrammeCover(programme: Programme, shape: Shape, rotation: Float = 0f): Modifier {
    val sharedScope = LocalProgrammeCoverSharedScope.current ?: return rotate(rotation).clip(shape)
    val animationScope = LocalProgrammeCoverAnimationScope.current ?: return rotate(rotation).clip(shape)
    val url = programme.coverUrl ?: return rotate(rotation).clip(shape)
    val sourceRotation = LocalProgrammeCoverTransitionState.current?.sourceRotation(programme) ?: 0f
    val motion = remember(programme.id, url) { ProgrammeCoverMotion(rotation) }
    fun rotationFor(visibility: EnterExitState): Float = if (visibility == EnterExitState.Visible) {
        rotation
    } else if (rotation == 0f) {
        sourceRotation
    } else {
        0f
    }
    return with(sharedScope) {
        val sharedContent = rememberSharedContentState(ProgrammeCoverKey(programme.id, url))
        sharedElement(
            sharedContent,
            animatedVisibilityScope = animationScope,
            boundsTransform = { initial, target ->
                motion.initialBounds = initial
                motion.targetBounds = target
                motion.initialRotation = rotationFor(animationScope.transition.currentState)
                motion.targetRotation = rotationFor(animationScope.transition.targetState)
                tween(400, easing = FastOutSlowInEasing)
            }
        ).layout { measurable, constraints ->
            val placeable = measurable.measure(constraints)
            layout(placeable.width, placeable.height) {
                if (!isLookingAhead && sharedContent.isMatchFound && sharedScope.isTransitionActive) {
                    coordinates?.let { placed ->
                        val position = lookaheadScopeCoordinates.localPositionOf(placed, Offset.Zero)
                        // Seeking and cancelled back gestures use the same bounds as ordinary navigation.
                        motion.update(Rect(position, placed.size.toSize()))
                    }
                }
                placeable.place(0, 0)
            }
        }.graphicsLayer {
            // Keep rotation inside the shared layer; ancestor transforms do not follow it into the overlay.
            rotationZ = if (sharedContent.isMatchFound && sharedScope.isTransitionActive) motion.rotation else rotation
        }.clip(shape)
    }
}
