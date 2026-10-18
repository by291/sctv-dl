package dev.sctvdl.feature.player.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.programme.ProgrammeSelection
import dev.sctvdl.feature.player.PlayerUiState
import dev.sctvdl.ui.programme.PlaybackCover

@Composable
internal fun PlaybackLoadingContent(
    state: PlayerUiState,
    selection: ProgrammeSelection?,
    onBack: () -> Unit,
    onRetry: () -> Unit
) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val videoHeight = inlinePlayerHeight(maxWidth, maxHeight, LocalDensity.current.fontScale)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
            PlaybackTopBar(onBack)
            if (selection != null) {
                // Accepted artwork must join the flight before history or source preparation finishes.
                PlaybackCover(
                    reference = selection.ref,
                    url = selection.content.coverUrl ?: selection.programme.coverUrl,
                    modifier = Modifier.fillMaxWidth().height(videoHeight).background(Color.Black),
                    videoReady = false
                )
            }
            StatePanel(
                if (state.loading) "准备播放" else "暂时无法播放",
                state.error?.message ?: "正在获取节目视频",
                state.loading,
                if (state.loading) null else onRetry
            )
        }
    }
}

internal fun inlinePlayerHeight(width: Dp, height: Dp, fontScale: Float): Dp =
    minOf(width * (9f / 16f), if (width > height) height * 0.4f else height)
        .coerceAtLeast(if (fontScale >= 1.5f) 208.dp else 176.dp).coerceAtMost(height)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlaybackTopBar(onBack: () -> Unit) {
    TopAppBar(
        modifier = Modifier.background(MaterialTheme.colorScheme.surface),
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = Color.Transparent,
            scrolledContainerColor = Color.Transparent
        ),
        title = { Text("节目播放") },
        navigationIcon = {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回节目单")
            }
        }
    )
}
