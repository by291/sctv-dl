package dev.sctvdl.player.ui

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.Player
import dev.sctvdl.player.model.PlaybackState
import kotlinx.coroutines.delay

/** Player-keyed interaction state; accessibility and focus can extend the normal hide deadline. */
internal class PlayerControlsVisibility {
    var visible by mutableStateOf(true)
        private set
    var interacting by mutableStateOf(false)
    var focused by mutableStateOf(false)
    var interactionCount by mutableIntStateOf(0)
        private set

    fun interact() {
        visible = true
        registerInteraction()
    }

    fun toggle() {
        visible = !visible
        registerInteraction()
    }

    fun registerInteraction() {
        interactionCount++
    }

    fun hide() {
        visible = false
    }

    fun keepVisible(state: PlaybackState, gestureInteracting: Boolean): Boolean =
        !state.playing || state.buffering || state.error != null || interacting || gestureInteracting || focused

    fun shouldShow(state: PlaybackState, enabled: Boolean, gestureInteracting: Boolean): Boolean =
        enabled && (visible || keepVisible(state, gestureInteracting))
}

@Composable
internal fun rememberPlayerControls(
    player: Player,
    state: PlaybackState,
    enabled: Boolean,
    gestureInteracting: Boolean
): PlayerControlsVisibility {
    val controls = remember(player) { PlayerControlsVisibility() }
    val accessibility = LocalAccessibilityManager.current
    val timeout = accessibility?.calculateRecommendedTimeoutMillis(
        originalTimeoutMillis = 3_500,
        containsIcons = true,
        containsText = true,
        containsControls = true
    ) ?: 3_500
    val keepVisible = controls.keepVisible(state, gestureInteracting)

    LaunchedEffect(controls.visible, keepVisible, controls.interactionCount, enabled, timeout) {
        if (enabled && controls.visible && !keepVisible) {
            delay(timeout)
            controls.hide()
        }
    }
    return controls
}

@Composable
internal fun rememberTouchExploration(): Boolean {
    val context = LocalContext.current
    val manager = remember(context) {
        context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    }
    var enabled by remember { mutableStateOf(manager.isTouchExplorationEnabled) }

    DisposableEffect(manager) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { enabled = it }
        manager.addTouchExplorationStateChangeListener(listener)
        onDispose { manager.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}
