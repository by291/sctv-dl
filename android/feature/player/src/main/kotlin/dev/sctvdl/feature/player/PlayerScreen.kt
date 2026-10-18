package dev.sctvdl.feature.player

import androidx.compose.runtime.Composable
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.ProgrammeSelection
import dev.sctvdl.feature.player.components.PlaybackContent
import dev.sctvdl.feature.player.components.PlaybackLoadingContent
import dev.sctvdl.player.model.PlaybackSource

@Composable
internal fun PlayerScreen(
    state: PlayerUiState,
    onBack: () -> Unit,
    onRetry: () -> Unit,
    onPosition: (Long) -> Unit,
    onDownload: (List<DownloadRequest>) -> Unit,
    wifiOnly: Boolean,
    host: PlaybackHost,
    previewSelection: ProgrammeSelection? = null
) {
    val selection = state.selection ?: previewSelection
    val content = state.content ?: selection?.content
    val broadcastDate = state.broadcastDate ?: selection?.broadcast?.date
    val variants = content?.let(::videoVariants).orEmpty()
    // Accepted list metadata renders the final page immediately, without a temporary loading destination.
    val source = state.source ?: if (state.loading && content != null && variants.isNotEmpty()) {
        PlaybackSource(content.id, content.title, variants)
    } else {
        null
    }
    if (source != null) {
        PlaybackContent(
            source,
            state.initialQuality,
            onBack,
            onPosition,
            content?.let { content ->
                broadcastDate?.let { date ->
                    { quality: Quality ->
                        onDownload(
                            listOf(
                                DownloadRequest(
                                    selection?.programme?.name ?: state.programmeName,
                                    date,
                                    content,
                                    quality,
                                    wifiOnly,
                                    selection
                                )
                            )
                        )
                    }
                }
            },
            programmeName = selection?.programme?.name ?: state.programmeName,
            broadcastDate = broadcastDate,
            host = host,
            history = state.history,
            coverUrl = content?.coverUrl ?: selection?.programme?.coverUrl,
            coverReference = selection?.ref,
            sourcePrepared = state.source != null
        )
    } else {
        PlaybackLoadingContent(state, selection, onBack, onRetry)
    }
}
