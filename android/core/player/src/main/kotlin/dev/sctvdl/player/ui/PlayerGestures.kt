package dev.sctvdl.player.ui

import android.os.SystemClock
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import kotlin.math.abs

/** Shared by the video ancestor and its blank gesture layer. */
internal class PlayerGesturePointers {
    var count = 0
    var cancelActive: (() -> Unit)? = null
}

/** Observes sibling controls too, without consuming their pointer input. */
internal fun Modifier.observePlayerPointers(pointers: PlayerGesturePointers): Modifier = pointerInput(pointers) {
    awaitPointerEventScope {
        while (true) {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            pointers.count = event.changes.count { it.pressed }
            if (pointers.count > 1) {
                pointers.cancelActive?.invoke()
            }
        }
    }
}

private const val GESTURE_EDGE_DP = 24
private const val MAX_SCRUB_DISTANCE_MS = 120_000L

private enum class GestureMode { AwaitingDirection, LongPress, Seek, AdjustControls }

/** Installed on the blank surface behind controls, so controls and menus keep their own input. */
internal fun Modifier.playerGestures(
    key: Any,
    fullscreen: Boolean,
    pointers: PlayerGesturePointers,
    position: () -> Long,
    duration: () -> Long?,
    playing: () -> Boolean,
    onTap: () -> Unit,
    onDoubleTap: () -> Unit,
    onSeek: (Long) -> Unit,
    onTemporarySpeed: (Boolean) -> Unit,
    environment: PlayerGestureEnvironment?,
    onInteraction: (Boolean) -> Unit,
    onHud: (String?) -> Unit
): Modifier = pointerInput(key, fullscreen) {
    var previousTap = 0L
    awaitEachGesture {
        val down = awaitFirstDown()
        if (pointers.count > 1) {
            return@awaitEachGesture
        }
        val edge = GESTURE_EDGE_DP * density
        if (down.position.x < edge || down.position.x > size.width - edge ||
            down.position.y < edge || down.position.y > size.height - edge
        ) {
            return@awaitEachGesture
        }

        val origin = down.position
        val start = position()
        val length = duration()?.takeIf { it > 0 }
        var mode = GestureMode.AwaitingDirection
        var target: Long? = null
        var isCancelled = false
        var isBoosting = false
        var lastPosition = origin
        val cancelGesture = {
            isCancelled = true
            if (isBoosting) {
                isBoosting = false
                onTemporarySpeed(false)
            }
            onInteraction(false)
            onHud(null)
        }
        pointers.cancelActive = cancelGesture
        onInteraction(true)

        try {
            while (true) {
                val timeout = if (mode != GestureMode.AwaitingDirection) {
                    Long.MAX_VALUE
                } else {
                    val deadline = down.uptimeMillis + viewConfiguration.longPressTimeoutMillis
                    (deadline - SystemClock.uptimeMillis()).coerceAtLeast(1)
                }
                val event = withTimeoutOrNull(timeout) {
                    awaitPointerEvent(PointerEventPass.Main)
                }
                if (isCancelled) {
                    break
                }
                if (event == null && mode == GestureMode.AwaitingDirection) {
                    // Timeout before a drag commits to long press, even if playback is paused.
                    mode = GestureMode.LongPress
                    isBoosting = startPlaybackBoost(playing, onTemporarySpeed, onHud)
                }
                if (event == null) {
                    continue
                }
                if (event.changes.size != 1 || event.changes.any { it.isConsumed }) {
                    isCancelled = true
                    break
                }
                val change = event.changes.first()
                if (!change.pressed) {
                    break
                }
                val displacement = change.position - origin
                val shouldCommitDirection = mode == GestureMode.AwaitingDirection &&
                    displacement.getDistance() > viewConfiguration.touchSlop
                if (shouldCommitDirection) {
                    mode = dragMode(displacement.x, displacement.y)
                }

                // Inline playback must leave vertical drags to the surrounding page.
                if (mode == GestureMode.AdjustControls && !fullscreen) {
                    isCancelled = true
                    break
                }

                if (mode == GestureMode.Seek && length != null) {
                    val scrubDistance = minOf(length, MAX_SCRUB_DISTANCE_MS)
                    val requested = start + displacement.x / size.width * scrubDistance
                    target = requested.toLong().coerceIn(0, length)
                    onHud(seekFeedback(target, start, length))
                    change.consume()
                } else if (mode == GestureMode.AdjustControls) {
                    val delta = (lastPosition.y - change.position.y) / size.height
                    val adjustsBrightness = origin.x < size.width / 2f
                    onHud(adjustControl(environment, delta, adjustsBrightness))
                    change.consume()
                }
                lastPosition = change.position
            }
            if (!isCancelled && mode == GestureMode.Seek) {
                target?.let(onSeek)
            }
            if (!isCancelled && mode == GestureMode.AwaitingDirection) {
                val now = down.uptimeMillis
                if (previousTap > 0 && now - previousTap <= viewConfiguration.doubleTapTimeoutMillis) {
                    previousTap = 0
                    onDoubleTap()
                } else {
                    previousTap = now
                    onTap()
                }
            }
        } finally {
            cancelGesture()
            if (pointers.cancelActive === cancelGesture) {
                pointers.cancelActive = null
            }
        }
    }
}

private fun startPlaybackBoost(
    playing: () -> Boolean,
    onTemporarySpeed: (Boolean) -> Unit,
    onHud: (String?) -> Unit
): Boolean {
    if (!playing()) {
        return false
    }

    onTemporarySpeed(true)
    onHud("2× 倍速播放")
    return true
}

private fun dragMode(horizontal: Float, vertical: Float): GestureMode =
    if (abs(horizontal) > abs(vertical)) GestureMode.Seek else GestureMode.AdjustControls

private fun seekFeedback(position: Long, start: Long, duration: Long): String {
    val offset = position - start
    val sign = if (offset >= 0) "+" else "−"
    return "进度 ${playbackTime(position)} / ${playbackTime(duration)} ($sign${playbackTime(abs(offset))})"
}

private fun adjustControl(environment: PlayerGestureEnvironment?, delta: Float, adjustsBrightness: Boolean): String? =
    if (adjustsBrightness) {
        environment?.adjustBrightness(delta)?.let { "亮度 $it%" }
    } else {
        environment?.adjustVolume(delta)?.let { "音量 $it%" }
    }
