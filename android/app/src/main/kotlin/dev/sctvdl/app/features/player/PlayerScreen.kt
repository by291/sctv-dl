package dev.sctvdl.app.features.player

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.sctvdl.design.QualitySheet
import dev.sctvdl.design.StatePanel
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.Quality
import dev.sctvdl.player.PlaybackSource
import dev.sctvdl.player.PlayerControls
import dev.sctvdl.player.PlayerSession
import dev.sctvdl.player.VideoSurface
import kotlinx.coroutines.delay

@Composable
fun PlayerScreen(
    state: PlayerUiState,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onPosition: (Long) -> Unit,
    onDownload: (List<DownloadRequest>) -> Unit,
    wifiOnly: Boolean
) {
    val source = state.source
    if (source != null) {
        PlaybackDestination(
            source,
            state.initialQuality,
            onBack,
            onPosition,
            state.content?.let { content ->
                state.broadcastDate?.let { date ->
                    { quality: Quality ->
                        onDownload(
                            listOf(
                                DownloadRequest(
                                    state.programmeName,
                                    date,
                                    content,
                                    quality,
                                    wifiOnly
                                )
                            )
                        )
                    }
                }
            }
        )
    } else {
        Column {
            TextButton(onClick = onBack) { Text("返回节目单") }
            StatePanel(
                if (state.loading) "准备播放" else "暂时无法播放",
                state.error?.message ?: "正在获取节目视频",
                state.loading,
                if (state.loading) null else onRetry
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaybackDestination(
    source: PlaybackSource,
    initialQuality: Quality,
    onBack: () -> Unit,
    onPosition: (Long) -> Unit,
    onDownload: ((Quality) -> Unit)? = null
) {
    val context = LocalContext.current
    val activity = context.mainActivity()
    val bridge = remember(activity) { PlaybackActivityBridge(activity) }
    val session = remember(source.id) { PlayerSession(context, initialQuality) }
    val playback by session.controller.state.collectAsStateWithLifecycle()
    val pip by (
        activity?.pictureInPicture
            ?: remember {
                kotlinx.coroutines.flow.MutableStateFlow(false)
            }
        ).collectAsStateWithLifecycle()
    var fullscreen by rememberSaveable { mutableStateOf(false) }
    var downloadSheet by rememberSaveable { mutableStateOf(false) }

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
    LaunchedEffect(fullscreen) { bridge.fullscreen(fullscreen) }
    DisposableEffect(session) {
        activity?.bindPlayer(session)
        onDispose {
            onPosition(session.controller.state.value.positionMs)
            activity?.unbindPlayer(session)
            bridge.fullscreen(false)
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
        val videoHeight = minOf(maxWidth * (9f / 16f), if (maxWidth > maxHeight) maxHeight * 0.4f else maxHeight)
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
                    },
                    actions = {
                        if (onDownload != null) {
                            IconButton(onClick = { downloadSheet = true }) {
                                Icon(
                                    Icons.Outlined.Download,
                                    "下载当前节目"
                                )
                            }
                        }
                    }
                )
            }
            Box(
                Modifier.fillMaxWidth().then(
                    if (fullscreen || pip) {
                        Modifier.weight(1f)
                    } else {
                        Modifier.height(videoHeight)
                    }
                ).background(Color.Black)
            ) {
                VideoSurface(session.player, Modifier.fillMaxSize())
                if (playback.buffering &&
                    !pip
                ) {
                    CircularProgressIndicator(
                        Modifier.align(Alignment.Center),
                        color = Color.White
                    )
                }
                playback.error?.takeUnless { pip }?.let { error ->
                    Surface(
                        Modifier.align(Alignment.Center).padding(16.dp),
                        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.96f),
                        shape = MaterialTheme.shapes.medium
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(error)
                            FilledTonalButton(onClick = session.controller::retry) { Text("重试播放") }
                        }
                    }
                }
            }
            if (!pip) {
                PlayerControls(
                    playback,
                    session.controller::togglePlay,
                    session.controller::seekTo,
                    session.controller::selectQuality,
                    session.controller::setSpeed,
                    fullscreen,
                    { fullscreen = !fullscreen },
                    { activity?.enterPlayerPictureInPicture() }
                )
                if (!fullscreen) {
                    Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(source.title, style = MaterialTheme.typography.titleLarge)
                        Text(
                            if (source.localUri != null) "本地视频" else "按下播放开始回看",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }
    }
    if (downloadSheet && onDownload != null) {
        QualitySheet(playback.variants, 1, {
            onDownload(it)
            downloadSheet = false
        }, { downloadSheet = false })
    }
}
