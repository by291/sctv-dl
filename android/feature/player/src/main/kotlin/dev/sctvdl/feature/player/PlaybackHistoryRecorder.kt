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

private const val PROGRESS_SAVE_INTERVAL_MS = 5_000L

/** Captures player progress for the repository’s independently owned write queue. */
internal class PlaybackHistoryRecorder(
    private val history: HistoryRepository,
    private val target: ViewingTarget,
    private val scope: CoroutineScope,
    private val now: () -> Long = System::currentTimeMillis
) {
    private var session: HistorySession? = null
    private var lastObservedSample: PlaybackState? = null
    private var latestSettledSample: PlaybackState? = null
    private var lastSaveAt: Long? = null
    private var isAcquiringSession = false
    private var isSeekPending = false
    private var invalidatedPosition: Long? = null
    private val mutableError = MutableStateFlow<String?>(null)
    val error = mutableError.asStateFlow()

    /** Acquire a history session and return its saved resume position. */
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
        val previous = lastObservedSample
        lastObservedSample = state
        if (!state.ready && !state.ended) {
            return
        }
        if (invalidatedPosition == state.positionMs && !state.playing) {
            return
        }
        latestSettledSample = state

        val didPause = previous?.playWhenReady == true && !state.playWhenReady
        val didEnd = state.ended && previous?.ended != true
        val didMove = previous?.positionMs != state.positionMs
        val savedAt = lastSaveAt
        val shouldSaveProgress = didMove && (savedAt == null || now() - savedAt >= PROGRESS_SAVE_INTERVAL_MS)

        if (isSeekPending || didPause || didEnd || shouldSaveProgress) {
            flush(state)
        }
    }

    fun onSeekCompleted(state: PlaybackState) {
        isSeekPending = true
        flush(state)
    }

    fun close(state: PlaybackState) = flush(state)

    fun retry(state: PlaybackState) {
        session = null
        invalidatedPosition = null
        flush(state)
    }

    fun flush(state: PlaybackState) {
        if (!state.ready && !state.ended) {
            return
        }
        lastObservedSample = state
        latestSettledSample = state

        val writeSession = session
        if (writeSession == null) {
            acquireForProgress(state.positionMs)
            return
        }

        isSeekPending = false
        val entry = ViewingEntry(
            target = target,
            positionMs = state.positionMs,
            durationMs = state.durationMs,
            viewedAt = Instant.ofEpochMilli(now()),
            completed = isViewingCompleted(state.positionMs, state.durationMs, state.ended)
        )
        lastSaveAt = now()

        val write = history.submit(writeSession, entry)
        scope.launch {
            try {
                val result = write.await()

                // A retry can replace this session while its earlier write is still queued.
                if (session !== writeSession) {
                    return@launch
                }
                when (result) {
                    HistoryWriteResult.Saved -> mutableError.value = null
                    HistoryWriteResult.Invalidated -> {
                        session = null
                        invalidatedPosition = state.positionMs
                    }
                }
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                if (session === writeSession) {
                    mutableError.value = "观看进度未保存，点击重试"
                }
            }
        }
    }

    private fun acquireForProgress(positionMs: Long) {
        // A snapshot invalidated by deletion cannot recreate the row at the same position.
        if (invalidatedPosition == positionMs || isAcquiringSession) {
            return
        }
        isAcquiringSession = true

        scope.launch {
            try {
                initialize()
                // A seek or pause can settle while begin() waits on the durable write queue.
                if (session != null) {
                    latestSettledSample?.let(::flush)
                }
            } finally {
                isAcquiringSession = false
            }
        }
    }
}
