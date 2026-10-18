package dev.sctvdl.feature.player.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LifecycleResumeEffect
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.feature.player.PlaybackHistoryRecorder
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackSource
import kotlinx.coroutines.delay

/** Binds a session to the destination entry; disposal follows the navigation leave animation. */
@Composable
internal fun rememberPlaybackSession(
    source: PlaybackSource,
    initialQuality: Quality,
    sourcePrepared: Boolean,
    fullscreen: Boolean,
    host: PlaybackHost,
    history: PlaybackHistoryRecorder?,
    onPosition: (Long) -> Unit
): PlayerSession {
    val currentHistory by rememberUpdatedState(history)
    val currentPrepared by rememberUpdatedState(sourcePrepared)
    val context = LocalContext.current
    val session = remember(source.id) { PlayerSession(context, initialQuality) }

    // Keep one player and artwork node during entry; only start media after resume/settings restoration.
    LaunchedEffect(source.id, source.variants, source.localUri, sourcePrepared) {
        if (sourcePrepared) session.controller.setSource(source, initialQuality)
    }

    LaunchedEffect(session, sourcePrepared) {
        if (!sourcePrepared) return@LaunchedEffect
        while (true) {
            session.controller.tick()
            onPosition(session.controller.state.value.positionMs)
            currentHistory?.onProgress(session.controller.state.value)
            delay(500)
        }
    }

    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) {
        session.controller.endTemporarySpeed()
        host.gestureEnvironment?.restoreBrightness()
        if (currentPrepared) currentHistory?.flush(session.controller.state.value)
    }

    LifecycleResumeEffect(fullscreen) {
        // Predictive previews are STARTED; only a committed destination may change the Activity window.
        host.fullscreen(fullscreen)
        // Keep the outgoing window intact through the leave animation; disposal below restores it.
        onPauseOrDispose { }
    }

    // Disposal happens after the leave animation; releasing on Back would tear down the outgoing video surface.
    DisposableEffect(session) {
        host.bindPlayer(session)
        onDispose {
            // Leaving before preparation must not replace a saved resume point with the empty player's zero.
            if (currentPrepared) {
                onPosition(session.controller.state.value.positionMs)
                currentHistory?.onProgress(session.controller.state.value)
                currentHistory?.close(session.controller.state.value)
            }
            host.unbindPlayer(session)
            host.fullscreen(false)
            session.release()
        }
    }

    return session
}
