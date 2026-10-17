package dev.sctvdl.feature.player

import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.history.isViewingCompleted
import dev.sctvdl.domain.history.resumePositionMs
import dev.sctvdl.domain.repository.HistoryRepository
import dev.sctvdl.domain.repository.HistorySession
import dev.sctvdl.domain.repository.HistoryWriteResult
import dev.sctvdl.player.model.PlaybackState
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Captures immutable progress only; durable submissions are owned by the repository, never the player. */
internal class PlaybackHistoryRecorder(
    private val history: HistoryRepository,
    private val target: ViewingTarget,
    private val scope: CoroutineScope,
    private val now: () -> Long = System::currentTimeMillis
) {
    private var session: HistorySession? = null
    private var last: PlaybackState? = null
    private var lastSaveAt: Long? = null
    private var acquiring = false
    private var seekPending = false
    private var invalidatedPosition: Long? = null
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()

    suspend fun initialize(): Long {
        try {
            session = history.begin(target)
            mutableError.value = null
        } catch (failure: CancellationException) {
            throw failure
        } catch (_: Exception) {
            mutableError.value = "无法读取观看记录，点击重试保存"
        }
        return resumePositionMs(session?.previous)
    }

    fun onProgress(state: PlaybackState) {
        val previous = last
        last = state
        if (!state.ready && !state.ended) return
        if (invalidatedPosition == state.positionMs && !state.playing) return

        val paused = previous?.playWhenReady == true && !state.playWhenReady
        val advanced = previous?.positionMs != state.positionMs
        if (seekPending || paused || (state.ended && previous?.ended != true) ||
            (advanced && (lastSaveAt == null || now() - requireNotNull(lastSaveAt) >= 5000))
        ) {
            flush(state)
        }
    }

    fun onSeekCompleted(state: PlaybackState) {
        seekPending = true
        flush(state)
    }

    fun close(state: PlaybackState) = flush(state)

    fun retry(state: PlaybackState) {
        session = null
        invalidatedPosition = null
        flush(state)
    }

    fun flush(state: PlaybackState) {
        if (!state.ready && !state.ended) return
        last = state
        val active = session
        if (active == null) {
            // An invalidated snapshot cannot recreate a deleted row. Only a later viewing event may begin again.
            if (invalidatedPosition == state.positionMs || acquiring) return
            acquiring = true
            scope.launch {
                try {
                    initialize()
                    if (session != null) flush(state)
                } finally {
                    acquiring = false
                }
            }
            return
        }
        seekPending = false
        val entry = ViewingEntry(
            target,
            state.positionMs,
            state.durationMs,
            Instant.ofEpochMilli(now()),
            isViewingCompleted(state.positionMs, state.durationMs, state.ended)
        )
        lastSaveAt = now()
        val write = history.submit(active, entry)
        scope.launch {
            try {
                when (write.await()) {
                    HistoryWriteResult.Saved -> mutableError.value = null
                    HistoryWriteResult.Invalidated -> {
                        session = null
                        invalidatedPosition = state.positionMs
                    }
                }
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                mutableError.value = "观看进度未保存，点击重试"
            }
        }
    }
}
