package dev.sctvdl.domain

import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.download.isActive
import dev.sctvdl.domain.download.supportedActions
import dev.sctvdl.domain.media.Quality
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadActionsTest {
    private val task = DownloadTask(
        "id", "1", "Episode", "Programme", LocalDate.of(2026, 10, 17), Quality.Standard,
        Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "a.mp4", false, createdAt = Instant.EPOCH
    )

    @Test fun legacyTasksCannotPauseButManagedPausedTasksCanResume() {
        assertFalse(DownloadAction.Pause in supportedActions(task.copy(state = DownloadState.Running)))
        val paused = task.copy(owner = DownloadOwner.Media3, state = DownloadState.Paused)
        assertTrue(paused.state.isActive)
        assertTrue(DownloadAction.Resume in supportedActions(paused))
        assertFalse(DownloadAction.RemoveRecord in supportedActions(paused))
    }

    @Test fun publicationFailureRetainsItsReservationAndOffersPublicationRetry() {
        val failed = task.copy(owner = DownloadOwner.Media3, state = DownloadState.Failed, cacheComplete = true)
        assertTrue(DownloadAction.Publish in supportedActions(failed))
        assertFalse(DownloadAction.Retry in supportedActions(failed))
        assertTrue(DownloadState.Finalizing.isActive)
    }
}
