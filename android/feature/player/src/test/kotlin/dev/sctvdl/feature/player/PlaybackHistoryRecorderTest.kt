package dev.sctvdl.feature.player

import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.testing.FakeHistory
import dev.sctvdl.player.model.PlaybackState
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PlaybackHistoryRecorderTest {
    private val target = ViewingTarget.LegacyDownload("7", "Episode", "Programme", LocalDate.of(2026, 10, 17))

    @Test fun throttlesProgressAndFlushesPauseSeekAndExit() = runTest {
        val repo = FakeHistory()
        var now = 0L
        val recorder = PlaybackHistoryRecorder(repo, target, backgroundScope) { now }
        recorder.initialize()
        val start = PlaybackState(ready = true, playing = true, playWhenReady = true, durationMs = 100_000)
        recorder.onProgress(start)
        now = 4000
        recorder.onProgress(start.copy(positionMs = 4000))
        assertEquals(1, repo.writes.size)
        now = 5000
        recorder.onProgress(start.copy(positionMs = 5000))
        recorder.onProgress(start.copy(positionMs = 5500, playing = false, playWhenReady = false))
        recorder.onSeekCompleted(start.copy(positionMs = 12_000))
        recorder.close(start.copy(positionMs = 13_000))
        assertEquals(listOf(0L, 5000L, 5500L, 12_000L, 13_000L), repo.writes.map { it.positionMs })
    }

    @Test fun pausedSeekFlushesWhenBufferingFinishesWithoutWaitingForPlayback() = runTest {
        val repo = FakeHistory()
        val recorder = PlaybackHistoryRecorder(repo, target, backgroundScope) { 1_000L }
        recorder.initialize()
        recorder.onProgress(PlaybackState(ready = true, positionMs = 0))
        val pending = PlaybackState(buffering = true, positionMs = 12_000)
        recorder.onSeekCompleted(pending)
        recorder.onProgress(pending)
        recorder.onProgress(pending.copy(buffering = false, ready = true))
        assertEquals(listOf(0L, 12_000L), repo.writes.map { it.positionMs })
    }

    @Test fun invalidationDoesNotImmediatelyResaveAndFailureRemainsRetryable() = runTest {
        val repo = FakeHistory()
        val recorder = PlaybackHistoryRecorder(repo, target, backgroundScope) { 10_000L }
        recorder.initialize()
        val state = PlaybackState(ready = true, positionMs = 12_000)
        repo.clear()
        recorder.flush(state)
        runCurrent()
        assertTrue(repo.entries.value.isEmpty())
        recorder.onProgress(state)
        runCurrent()
        assertTrue(repo.entries.value.isEmpty())

        repo.fail = true
        recorder.onSeekCompleted(state.copy(positionMs = 13_000))
        runCurrent()
        assertNotNull(recorder.error.value)
        repo.fail = false
        recorder.retry(state.copy(positionMs = 14_000))
        runCurrent()
        assertEquals(14_000, repo.entries.value.single().positionMs)
    }
}
