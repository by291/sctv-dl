package dev.sctvdl.data

import dev.sctvdl.data.downloads.DownloadReconciler
import dev.sctvdl.data.downloads.SystemDownloadSnapshot
import dev.sctvdl.domain.DownloadReason
import dev.sctvdl.domain.DownloadState
import dev.sctvdl.domain.DownloadTask
import dev.sctvdl.domain.Quality
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadReconcilerTest {
    private val gateway = FakeDownloadGateway()
    private val task = DownloadTask(
        "task",
        "1",
        "新闻",
        "栏目",
        LocalDate.of(
            2026,
            10,
            6
        ),
        Quality.Standard,
        Quality.Standard,
        "https://fscgc.scgchc.com/a.mp4",
        "unique.mp4",
        false,
        createdAt = Instant.EPOCH
    )

    @Test fun crashAfterEnqueueRecoversOnlyAnUnambiguousDestination() = runTest {
        val snapshot = SystemDownloadSnapshot(
            99,
            task.url,
            gateway.destinationFor(task.filename),
            DownloadState.Running,
            100,
            null
        )
        val recovered = DownloadReconciler(gateway).resolve(task, listOf(snapshot))
        assertEquals(99L, recovered.systemId)
        assertEquals(DownloadState.Running, recovered.state)
        assertEquals(100L, recovered.bytes)
        assertNull(recovered.totalBytes)
        val ambiguous = DownloadReconciler(gateway).resolve(
            task,
            listOf(
                snapshot,
                snapshot.copy(id = 100)
            )
        )
        assertEquals(DownloadState.Failed, ambiguous.state)
        assertEquals(DownloadReason.Ambiguous, ambiguous.reasonCode)
        assertNull(ambiguous.systemId)
        assertTrue(gateway.requests.isEmpty())
    }

    @Test fun waitingIsTruthfulAndDeletedCompletedFilesBecomeMissing() = runTest {
        val pending = task.copy(systemId = 99, state = DownloadState.Pending)
        val waiting = SystemDownloadSnapshot(
            99,
            task.url,
            gateway.destinationFor(task.filename),
            DownloadState.Waiting,
            1024,
            null,
            reason = "等待 Wi-Fi",
            reasonCode = DownloadReason.Wifi
        )
        assertEquals(
            DownloadReason.Wifi,
            DownloadReconciler(gateway).resolve(
                pending,
                listOf(waiting)
            ).reasonCode
        )
        val complete = waiting.copy(
            state = DownloadState.Completed,
            contentUri = "content://downloads/99",
            reason = null
        )
        assertEquals(
            DownloadState.Completed,
            DownloadReconciler(gateway).resolve(
                pending,
                listOf(complete)
            ).state
        )
        gateway.available = false
        assertEquals(
            DownloadState.Missing,
            DownloadReconciler(gateway).resolve(
                pending,
                listOf(complete)
            ).state
        )
    }
}
