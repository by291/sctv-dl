package dev.sctvdl.feature.player

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import dev.sctvdl.design.components.StatePanel
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.feature.player.components.PlaybackContent

@Composable
internal fun PlayerScreen(
    state: PlayerUiState,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onPosition: (Long) -> Unit,
    onDownload: (List<DownloadRequest>) -> Unit,
    wifiOnly: Boolean,
    host: PlaybackHost
) {
    val source = state.source
    if (source != null) {
        PlaybackContent(
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
            },
            programmeName = state.programmeName,
            broadcastDate = state.broadcastDate,
            host = host
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
