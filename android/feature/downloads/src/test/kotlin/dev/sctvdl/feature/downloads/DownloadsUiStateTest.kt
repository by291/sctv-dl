package dev.sctvdl.feature.downloads

import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.testing.fixtureTask
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadsUiStateTest {
    @Test fun eachLifecycleStateBelongsToExactlyOneSpecificFilter() {
        val expected = mapOf(
            DownloadState.Preparing to "Active",
            DownloadState.Pending to "Active",
            DownloadState.Running to "Active",
            DownloadState.Waiting to "Active",
            DownloadState.Paused to "Active",
            DownloadState.Finalizing to "Active",
            DownloadState.Completed to "Completed",
            DownloadState.Failed to "Unfinished",
            DownloadState.Cancelled to "Cancelled",
            DownloadState.Missing to "Removed"
        )

        DownloadState.entries.forEach { state ->
            val task = fixtureTask(state)
            val filters = DownloadFilter.entries.filter { it != DownloadFilter.All && it.includes(task) }

            assertEquals(state.name, listOf(expected.getValue(state)), filters.map { it.name })
        }
    }

    @Test fun allTasksUseActiveCompletedFailedCancelledAndRemovedGroupOrder() {
        val tasks = listOf(
            fixtureTask(DownloadState.Missing, "removed"),
            fixtureTask(DownloadState.Cancelled, "cancelled"),
            fixtureTask(DownloadState.Failed, "failed"),
            fixtureTask(DownloadState.Running, "active"),
            fixtureTask(DownloadState.Completed, "complete")
        )

        val visible = DownloadsUiState(tasks = tasks).visible

        assertEquals(listOf("active", "complete", "failed", "cancelled", "removed"), visible.map { it.id })
    }

    @Test fun eachGroupSortsNewestTasksFirstAndBreaksTimestampTiesById() {
        val states = listOf(
            DownloadState.Completed,
            DownloadState.Running,
            DownloadState.Failed,
            DownloadState.Cancelled,
            DownloadState.Missing
        )
        val tasks = states.flatMap { state ->
            listOf(
                fixtureTask(state, "${state.name}-old").copy(createdAt = Instant.ofEpochSecond(1)),
                fixtureTask(state, "${state.name}-b").copy(createdAt = Instant.ofEpochSecond(2)),
                fixtureTask(state, "${state.name}-a").copy(createdAt = Instant.ofEpochSecond(2))
            )
        }

        states.forEach { state ->
            val filter = DownloadFilter.entries.first { it != DownloadFilter.All && it.includes(fixtureTask(state)) }
            val visible = DownloadsUiState(tasks = tasks, tab = filter).visible

            assertEquals(
                state.name,
                listOf("${state.name}-a", "${state.name}-b", "${state.name}-old"),
                visible.map { it.id }
            )
        }
    }

    @Test fun repositoryOrderAndProgressUpdatesDoNotMoveTasksWithinTheirGroup() {
        val older = fixtureTask(DownloadState.Running, "older").copy(createdAt = Instant.ofEpochSecond(1))
        val newer = fixtureTask(DownloadState.Running, "newer").copy(createdAt = Instant.ofEpochSecond(2))
        val initial = DownloadsUiState(tasks = listOf(older, newer))
        val updated = initial.copy(
            tasks = listOf(
                newer.copy(bytes = 100, revision = 2, totalBytes = 1_000),
                older.copy(bytes = 900, revision = 3, totalBytes = 1_000)
            )
        )

        assertEquals(listOf("newer", "older"), initial.visible.map { it.id })
        assertEquals(listOf("newer", "older"), updated.visible.map { it.id })
    }
}
