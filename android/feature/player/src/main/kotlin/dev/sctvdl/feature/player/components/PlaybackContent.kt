package dev.sctvdl.feature.player.components

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.design.theme.TouchTarget
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ContentRef
import dev.sctvdl.feature.player.PlaybackHistoryRecorder
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.player.ui.PlayerVideo
import dev.sctvdl.ui.downloads.DownloadQualitySheet
import dev.sctvdl.ui.programme.PlaybackCover
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay

private val PlayerDateLabel = DateTimeFormatter.ofPattern("yyyy年M月d日", Locale.SIMPLIFIED_CHINESE)

@Composable
internal fun PlaybackContent(
    source: PlaybackSource,
    initialQuality: Quality,
    onBack: () -> Unit,
    onPosition: (Long) -> Unit,
    onDownload: ((Quality) -> Unit)? = null,
    programmeName: String? = null,
    broadcastDate: LocalDate? = null,
    host: PlaybackHost,
    history: PlaybackHistoryRecorder? = null,
    coverUrl: String? = null,
    coverReference: ContentRef? = null,
    sourcePrepared: Boolean = true
) {
    val currentHistory by rememberUpdatedState(history)
    val currentPrepared by rememberUpdatedState(sourcePrepared)
    val context = LocalContext.current
    val session = remember(source.id) { PlayerSession(context, initialQuality) }
    val playback by session.controller.state.collectAsStateWithLifecycle()
    val pip by host.pictureInPicture.collectAsStateWithLifecycle()

    var fullscreen by rememberSaveable { mutableStateOf(false) }
    var downloadSheet by rememberSaveable(source.id) { mutableStateOf(false) }

    val canDownload = onDownload != null && source.localUri == null && source.variants.isNotEmpty()

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

    BackHandler(fullscreen && !pip) { fullscreen = false }

    val back = {
        if (fullscreen) {
            fullscreen = false
        } else {
            session.controller.pauseForDismissal()
            onBack()
        }
    }

    val scroll = rememberScrollState()

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val videoHeight = inlinePlayerHeight(maxWidth, maxHeight, LocalDensity.current.fontScale)
        Column(
            Modifier.fillMaxSize().then(
                if (!fullscreen && !pip) Modifier.verticalScroll(scroll) else Modifier
            )
        ) {
            if (!fullscreen && !pip) {
                PlaybackTopBar(back)
            }
            PlayerVideo(
                player = session.player,
                state = playback,
                onQuality = session.controller::selectQuality,
                onSpeed = session.controller::setSpeed,
                fullscreen = fullscreen,
                onFullscreen = {
                    session.controller.endTemporarySpeed()
                    fullscreen = !fullscreen
                },
                onPip = if (host.supportsPictureInPicture) {
                    { host.enterPictureInPicture() }
                } else {
                    null
                },
                onRetry = session.controller::retry,
                onTogglePlay = {
                    session.controller.togglePlay()
                    currentHistory?.onProgress(session.controller.state.value)
                },
                onSeek = {
                    session.controller.seekTo(it)
                    currentHistory?.onSeekCompleted(session.controller.state.value)
                },
                modifier = Modifier.fillMaxWidth().then(
                    if (fullscreen || pip) Modifier.weight(1f) else Modifier.height(videoHeight)
                ),
                controlsEnabled = !pip && sourcePrepared,
                onTemporarySpeed = { active ->
                    if (active) session.controller.beginTemporarySpeed() else session.controller.endTemporarySpeed()
                },
                gestureEnvironment = host.gestureEnvironment,
                artwork = {
                    PlaybackCover(
                        reference = if (fullscreen || pip) null else coverReference,
                        url = coverUrl,
                        modifier = Modifier.fillMaxSize(),
                        videoReady = playback.firstFrameRendered
                    )
                }
            )
            if (history != null) {
                val historyError by history.error.collectAsStateWithLifecycle()
                historyError?.let { message ->
                    androidx.compose.material3.TextButton(onClick = {
                        history.retry(session.controller.state.value)
                    }) { Text(message) }
                }
            }
            if (!pip) {
                if (!fullscreen) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                        Column(
                            Modifier.widthIn(max = 720.dp).fillMaxWidth().padding(20.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text(source.title, Modifier.fillMaxWidth(), style = MaterialTheme.typography.titleLarge)
                            val contextLabel = if (source.localUri != null) {
                                "本地视频"
                            } else {
                                listOfNotNull(programmeName, broadcastDate?.format(PlayerDateLabel)).joinToString(" · ")
                            }
                            if (contextLabel.isNotBlank()) {
                                Text(
                                    contextLabel,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodyMedium
                                )
                            }
                            if (canDownload) {
                                Button(
                                    onClick = { downloadSheet = true },
                                    modifier = Modifier.fillMaxWidth().heightIn(min = TouchTarget)
                                ) {
                                    Icon(Icons.Outlined.Download, null, Modifier.size(20.dp))
                                    Spacer(Modifier.width(8.dp))
                                    Text("下载节目")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (downloadSheet && canDownload) {
        DownloadQualitySheet(source.variants, 1, {
            onDownload(it)
            downloadSheet = false
        }, { downloadSheet = false })
    }
}
