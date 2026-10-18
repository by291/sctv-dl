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
            if (pointers.count > 1) pointers.cancelActive?.invoke()
        }
    }
}

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
        if (pointers.count > 1) return@awaitEachGesture
        val edge = 24 * density
        if (down.position.x < edge || down.position.x > size.width - edge ||
            down.position.y < edge || down.position.y > size.height - edge
        ) {
            return@awaitEachGesture
        }
        val origin = down.position
        val start = position()
        val length = duration()?.takeIf { it > 0 }
        var axis = 0
        var target: Long? = null
        var longPress = false
        var cancelled = false
        var boosting = false
        var lastPosition = origin
        val cancelGesture = {
            cancelled = true
            if (boosting) {
                boosting = false
                onTemporarySpeed(false)
            }
            onInteraction(false)
            onHud(null)
        }
        pointers.cancelActive = cancelGesture
        onInteraction(true)
        try {
            while (true) {
                val timeout = if (axis != 0 || longPress) {
                    Long.MAX_VALUE
                } else {
                    (
                        down.uptimeMillis + viewConfiguration.longPressTimeoutMillis - SystemClock.uptimeMillis()
                        ).coerceAtLeast(1)
                }
                val event = withTimeoutOrNull(timeout) {
                    awaitPointerEvent(PointerEventPass.Main)
                }
                if (cancelled) break
                if (event == null) {
                    if (axis == 0 && !longPress) {
                        longPress = true
                        if (playing()) {
                            boosting = true
                            onTemporarySpeed(true)
                            onHud("2× 倍速播放")
                        }
                    }
                    continue
                }
                if (event.changes.size != 1 || event.changes.any { it.isConsumed }) {
                    cancelled = true
                    break
                }
                val change = event.changes.first()
                if (!change.pressed) break
                val displacement = change.position - origin
                if (axis == 0 && !longPress && displacement.getDistance() > viewConfiguration.touchSlop) {
                    axis = if (abs(displacement.x) > abs(displacement.y)) 1 else 2
                    if (axis == 2 && !fullscreen) {
                        cancelled = true
                        break
                    }
                }
                if (axis == 1 && length != null) {
                    target =
                        (start + displacement.x / size.width * minOf(length, 120_000L)).toLong().coerceIn(0, length)
                    val offset = target - start
                    val sign = if (offset >= 0) "+" else "−"
                    onHud("进度 ${playbackTime(target)} / ${playbackTime(length)} ($sign${playbackTime(abs(offset))})")
                    change.consume()
                } else if (axis == 2) {
                    val delta = (lastPosition.y - change.position.y) / size.height
                    val percent = if (origin.x < size.width / 2f) {
                        environment?.adjustBrightness(delta)?.let { "亮度 $it%" }
                    } else {
                        environment?.adjustVolume(delta)?.let { "音量 $it%" }
                    }
                    onHud(percent)
                    change.consume()
                }
                lastPosition = change.position
            }
            if (!cancelled && axis == 1) target?.let(onSeek)
            if (!cancelled && axis == 0 && !longPress) {
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
            if (pointers.cancelActive === cancelGesture) pointers.cancelActive = null
        }
    }
}
