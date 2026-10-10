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
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.design.theme.TouchTarget
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.feature.player.PlaybackHost
import dev.sctvdl.player.media3.PlayerSession
import dev.sctvdl.player.model.PlaybackSource
import dev.sctvdl.player.ui.PlayerVideo
import dev.sctvdl.ui.downloads.DownloadQualitySheet
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.delay

private val PlayerDateLabel = DateTimeFormatter.ofPattern("yyyy年M月d日", Locale.SIMPLIFIED_CHINESE)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlaybackContent(
    source: PlaybackSource,
    initialQuality: Quality,
    onBack: () -> Unit,
    onPosition: (Long) -> Unit,
    onDownload: ((Quality) -> Unit)? = null,
    programmeName: String? = null,
    broadcastDate: LocalDate? = null,
    host: PlaybackHost
) {
    val context = LocalContext.current
    val session = remember(source.id) { PlayerSession(context, initialQuality) }
    val playback by session.controller.state.collectAsStateWithLifecycle()
    val pip by host.pictureInPicture.collectAsStateWithLifecycle()
    var fullscreen by rememberSaveable { mutableStateOf(false) }
    var downloadSheet by rememberSaveable(source.id) { mutableStateOf(false) }
    val canDownload = onDownload != null && source.localUri == null && source.variants.isNotEmpty()

    LaunchedEffect(
        source.id,
        source.variants,
        source.localUri
    ) { session.controller.setSource(source) }
    LaunchedEffect(session) {
        while (true) {
            session.controller.tick()
            onPosition(session.controller.state.value.positionMs)
            delay(500)
        }
    }
    LaunchedEffect(fullscreen) { host.fullscreen(fullscreen) }
    DisposableEffect(session) {
        host.bindPlayer(session)
        onDispose {
            onPosition(session.controller.state.value.positionMs)
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
    val minimumVideoHeight = if (LocalDensity.current.fontScale >= 1.5f) 208.dp else 176.dp
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val videoHeight = minOf(maxWidth * (9f / 16f), if (maxWidth > maxHeight) maxHeight * 0.4f else maxHeight)
            .coerceAtLeast(minimumVideoHeight).coerceAtMost(maxHeight)
        Column(
            Modifier.fillMaxSize().then(
                if (!fullscreen && !pip) Modifier.verticalScroll(scroll) else Modifier
            )
        ) {
            if (!fullscreen && !pip) {
                TopAppBar(
                    title = { Text("节目播放") },
                    navigationIcon = {
                        IconButton(onClick = back) {
                            Icon(
                                Icons.AutoMirrored.Outlined.ArrowBack,
                                "返回节目单"
                            )
                        }
                    }
                )
            }
            PlayerVideo(
                player = session.player,
                state = playback,
                onQuality = session.controller::selectQuality,
                onSpeed = session.controller::setSpeed,
                fullscreen = fullscreen,
                onFullscreen = { fullscreen = !fullscreen },
                onPip = if (host.supportsPictureInPicture) {
                    { host.enterPictureInPicture() }
                } else {
                    null
                },
                onRetry = session.controller::retry,
                modifier = Modifier.fillMaxWidth().then(
                    if (fullscreen || pip) Modifier.weight(1f) else Modifier.height(videoHeight)
                ),
                controlsEnabled = !pip
            )
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
