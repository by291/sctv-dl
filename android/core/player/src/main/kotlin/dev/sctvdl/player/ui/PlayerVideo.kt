@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.player.ui

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.PictureInPictureAlt
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.media3.common.Player
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.player.model.PlaybackState
import kotlinx.coroutines.delay

@Composable
fun PlayerVideo(
    player: Player,
    state: PlaybackState,
    onQuality: (Quality) -> Unit,
    onSpeed: (Float) -> Unit,
    fullscreen: Boolean,
    onFullscreen: () -> Unit,
    onPip: (() -> Unit)?,
    onRetry: () -> Unit,
    onTogglePlay: () -> Unit,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
    controlsEnabled: Boolean = true,
    artwork: (@Composable () -> Unit)? = null,
    onTemporarySpeed: (Boolean) -> Unit = {},
    gestureEnvironment: PlayerGestureEnvironment? = null
) {
    val pointers = remember(player) { PlayerGesturePointers() }
    val configuration = LocalConfiguration.current
    val context = LocalContext.current
    val exploration = remember(context) {
        context.getSystemService(
            Context.ACCESSIBILITY_SERVICE
        ) as AccessibilityManager
    }
    var touchExploration by remember { mutableStateOf(exploration.isTouchExplorationEnabled) }
    var gestureEpoch by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) {
        gestureEpoch++
        onTemporarySpeed(false)
    }
    DisposableEffect(exploration) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener {
            touchExploration = it
        }
        exploration.addTouchExplorationStateChangeListener(listener)
        onDispose { exploration.removeTouchExplorationStateChangeListener(listener) }
    }
    val latestState by rememberUpdatedState(state)
    var hintEligible by remember(player, gestureEnvironment) {
        mutableStateOf(gestureEnvironment?.needsGestureHint() == true)
    }
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val windowFocused = LocalWindowInfo.current.isWindowFocused
    val showHint = fullscreen && controlsEnabled && hintEligible && !touchExploration &&
        lifecycleState.isAtLeast(Lifecycle.State.RESUMED) && windowFocused
    var gestureInteracting by remember(player) { mutableStateOf(false) }
    var hud by remember(player) { mutableStateOf<String?>(null) }
    var controlsVisible by remember(player) { mutableStateOf(true) }
    var interacting by remember(player) { mutableStateOf(false) }
    var focused by remember(player) { mutableStateOf(false) }
    var interactionCount by remember(player) { mutableIntStateOf(0) }
    val accessibility = LocalAccessibilityManager.current
    val interact: () -> Unit = {
        controlsVisible = true
        interactionCount++
    }
    val controlsTimeout = accessibility?.calculateRecommendedTimeoutMillis(
        originalTimeoutMillis = 3_500,
        containsIcons = true,
        containsText = true,
        containsControls = true
    ) ?: 3_500
    val keepControls =
        !state.playing || state.buffering || state.error != null || interacting || gestureInteracting || focused
    val showControls = controlsEnabled && (controlsVisible || keepControls)

    LaunchedEffect(controlsVisible, keepControls, interactionCount, controlsEnabled, controlsTimeout) {
        if (controlsEnabled && controlsVisible && !keepControls) {
            delay(controlsTimeout)
            controlsVisible = false
        }
    }

    BoxWithConstraints(
        modifier.background(Color.Black).observePlayerPointers(pointers).then(
            if (controlsEnabled) {
                Modifier.semantics {
                    onClick("显示播放控件") {
                        interact()
                        true
                    }
                }.onPreviewKeyEvent {
                    interact()
                    false
                }.onFocusChanged {
                    focused = it.hasFocus
                    if (it.hasFocus) interact()
                }.focusable()
            } else {
                Modifier
            }
        )
    ) {
        val menuMaxHeight = (maxHeight - 64.dp).coerceAtLeast(48.dp)
        VideoSurface(player, Modifier.fillMaxSize())
        // The owner retains artwork for shared return transitions after the first frame.
        artwork?.invoke()
        if (controlsEnabled && !touchExploration) {
            Box(
                Modifier.fillMaxSize().playerGestures(
                    listOf(
                        player,
                        gestureEpoch,
                        state.playing,
                        state.sourceId,
                        state.quality,
                        state.phase,
                        state.error,
                        state.ended,
                        configuration.orientation,
                        configuration.screenWidthDp,
                        configuration.screenHeightDp
                    ),
                    fullscreen, pointers, {
                        latestState.positionMs
                    }, { latestState.durationMs }, { latestState.playing },
                    {
                        controlsVisible = !controlsVisible
                        interactionCount++
                    }, onTogglePlay, onSeek,
                    onTemporarySpeed, gestureEnvironment, {
                        gestureInteracting = it
                        if (it) interactionCount++
                    }, { hud = it }
                )
            )
        }
        hud?.takeIf { controlsEnabled }?.let {
            Text(
                it,
                Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.7f)).padding(12.dp),
                color = Color.White
            )
        }

        if (showHint && hud == null) {
            Column(
                Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.8f)).padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("双击播放/暂停 · 横滑快进 · 左侧亮度/右侧音量 · 长按倍速", color = Color.White)
                // Explicit acknowledgement also handles non-focusable system overlays:
                // elapsed time alone cannot establish that the user saw this hint.
                TextButton(onClick = {
                    gestureEnvironment?.acknowledgeGestureHint()
                    hintEligible = false
                }) { Text("知道了", color = Color.White) }
            }
        }

        if (showControls) {
            Box(
                Modifier.fillMaxSize().focusGroup()
            ) {
                Box(
                    Modifier.align(Alignment.BottomCenter).fillMaxWidth().heightIn(min = 96.dp)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.72f))))
                )
                onPip?.let { action ->
                    Box(
                        Modifier.align(Alignment.TopCenter).fillMaxWidth().height(72.dp)
                            .background(
                                Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent))
                            )
                    )
                    IconButton(
                        onClick = {
                            interact()
                            action()
                        },
                        modifier = Modifier.align(Alignment.TopEnd).padding(4.dp)
                    ) {
                        Icon(Icons.Outlined.PictureInPictureAlt, "进入画中画", tint = Color.White)
                    }
                }
                Box(Modifier.align(Alignment.BottomCenter)) {
                    PlayerControls(
                        state,
                        onTogglePlay,
                        onSeek,
                        onQuality,
                        onSpeed,
                        fullscreen,
                        onFullscreen,
                        interact,
                        { interacting = it },
                        menuMaxHeight
                    )
                }
            }
        }
        if (state.buffering && controlsEnabled) {
            CircularProgressIndicator(Modifier.align(Alignment.Center), color = MaterialTheme.colorScheme.primary)
        }
        state.notice?.takeIf { controlsEnabled && state.error == null }?.let { notice ->
            Text(
                notice,
                Modifier.align(Alignment.TopStart).padding(top = 8.dp, start = 16.dp, end = 60.dp),
                color = Color.White,
                style = MaterialTheme.typography.labelMedium
            )
        }
        state.error?.takeIf { controlsEnabled }?.let { error ->
            // Keep recovery above the transport row so quality/fullscreen remain reachable.
            Box(Modifier.align(Alignment.TopStart).padding(top = 8.dp, start = 16.dp, end = 60.dp)) {
                TextButton(
                    onClick = {
                        interact()
                        onRetry()
                    },
                    modifier = Modifier.semantics { contentDescription = "重试播放" }
                ) {
                    Text(error, color = Color.White, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}
