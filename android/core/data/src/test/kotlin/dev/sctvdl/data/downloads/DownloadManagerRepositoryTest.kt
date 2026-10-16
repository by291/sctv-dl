package dev.sctvdl.data.downloads

import dev.sctvdl.data.downloads.DownloadManagerRepository
import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.data.downloads.platform.PlatformDownloadGateway
import dev.sctvdl.data.downloads.platform.SystemDownloadSnapshot
import dev.sctvdl.data.downloads.preflight.MediaPreflight
import dev.sctvdl.data.downloads.preflight.ProbeResponse
import dev.sctvdl.domain.download.DownloadReason
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ProgrammeContent
import java.time.Clock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DownloadManagerRepositoryTest {
    private val clock = Clock.fixed(Instant.parse("2026-10-07T00:00:00Z"), ZoneOffset.UTC)

    private fun request(id: String, smoothOnly: Boolean = false) = DownloadRequest(
        "新闻栏目",
        LocalDate.of(
            2026,
            10,
            6
        ),
        ProgrammeContent(
            id,
            "新闻 $id",
            standardUrl = if (smoothOnly) null else "https://fscgc.scgchc.com/$id.mp4",
            smoothUrl = "https://fscgc.scgchc.com/$id-smooth.mp4"
        ),
        Quality.Standard,
        true
    )

    @Test fun historicalCdnDownloadsReachTheSystemQueue() = runTest {
        val url = "https://fscgc.sctv-tf.com/NewsTV/2021/02/09/archive.mp4"
        val store = FakeDownloadStore()
        val gateway = FakeDownloadGateway()
        val probed = mutableListOf<String>()
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight { target, _, _ ->
                probed.add(target)
                ProbeResponse(200, "video/mp4", 4096)
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        val historical = request("60888").copy(
            content = ProgrammeContent("60888", "音你而来", standardUrl = url)
        )

        val result = repo.enqueue(listOf(historical))

        assertEquals(1, result.queued)
        assertTrue(result.failures.isEmpty())
        assertEquals(listOf(url), probed)
        assertEquals(url, gateway.requests.single().url)
        assertEquals(url, store.all().single().url)
    }

    @Test fun anOldSystemQueryCannotInvalidateANewSubmission() = runTest {
        val store = FakeDownloadStore()
        val native = FakeDownloadGateway()
        val queried = CompletableDeferred<Unit>()
        val resumeQuery = CompletableDeferred<Unit>()
        val gateway = object : PlatformDownloadGateway by native {
            override suspend fun queryOwned(): List<dev.sctvdl.data.downloads.platform.SystemDownloadSnapshot> {
                val snapshots = native.queryOwned()
                queried.complete(Unit)
                resumeQuery.await()
                return snapshots
            }
        }
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight { _, _, _ ->
                ProbeResponse(200, "video/mp4", 10)
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        val reconciliation = launch { repo.reconcile() }
        queried.await()
        val submission = async { repo.enqueue(listOf(request("1"))) }
        runCurrent()
        resumeQuery.complete(Unit)
        reconciliation.join()
        assertEquals(1, submission.await().queued)
        assertEquals(DownloadState.Pending, store.all().single().state)
        assertEquals(0, repo.enqueue(listOf(request("1"))).queued)
        assertEquals(1, native.requests.size)
    }

    @Test fun aReservationFailurePreservesEarlierSuccessAndContinuesTheBatch() = runTest {
        val rows = FakeDownloadStore()
        val store = object : DownloadStore by rows {
            override suspend fun reserve(task: DownloadTask): Boolean {
                if (task.contentId == "2") throw IllegalStateException("temporary storage failure")
                return rows.reserve(task)
            }
        }
        val gateway = FakeDownloadGateway()
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight { _, _, _ ->
                ProbeResponse(200, "video/mp4", 10)
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        val result = repo.enqueue(listOf(request("1"), request("2"), request("3")))
        assertEquals(2, result.queued)
        assertEquals(listOf("2"), result.failures.map { it.contentId })
        assertEquals(listOf("1", "3"), store.all().map { it.contentId })
        assertEquals(2, gateway.requests.size)
    }

    @Test fun partialBatchFailureAndQualityFallbackReportActualQueuedTasks() = runTest {
        val store = FakeDownloadStore()
        val gateway = FakeDownloadGateway()
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight {
                    url,
                    _,
                    _
                ->
                if (url.endsWith("2.mp4")) {
                    ProbeResponse(
                        403,
                        "text/html"
                    )
                } else {
                    ProbeResponse(
                        200,
                        "video/mp4",
                        100
                    )
                }
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        val result = repo.enqueue(listOf(request("1", true), request("2")))
        assertEquals(1, result.queued)
        assertEquals(1, result.fallbacks)
        assertEquals(listOf("2"), result.failures.map { it.contentId })
        assertTrue(gateway.requests.single().filename.contains("流畅"))
        assertTrue(gateway.requests.single().wifiOnly)
        val duplicate = repo.enqueue(listOf(request("1", true)))
        assertEquals(0, duplicate.queued)
        assertEquals(1, gateway.requests.size)
    }

    @Test fun cancellationDuringPreflightNeverEnqueuesAndHistoryRemovalLeavesFilesAlone() = runTest {
        val store = FakeDownloadStore()
        val gateway = FakeDownloadGateway()
        val gate = CompletableDeferred<Unit>()
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight { _, _, _ ->
                gate.await()
                ProbeResponse(200, "video/mp4", 10)
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        val job = launch { repo.enqueue(listOf(request("1"))) }
        runCurrent()
        assertEquals(DownloadState.Preparing, store.all().single().state)
        repo.cancel(store.all().single().id)
        gate.complete(Unit)
        job.join()
        assertTrue(gateway.requests.isEmpty())
        assertEquals(DownloadState.Cancelled, store.all().single().state)
        store.update(
            store.all().single().copy(
                state = DownloadState.Completed,
                systemId = 42,
                contentUri = "content://downloads/42"
            )
        )
        repo.removeRecord(store.all().single().id)
        assertTrue(store.all().isEmpty())
        assertTrue(gateway.removed.isEmpty())
    }

    @Test fun failedRetriesKeepOneDurableRecordAndUseANewDestination() = runTest {
        val store = FakeDownloadStore()
        val gateway = FakeDownloadGateway().apply { failEnqueue = true }
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight {
                    _,
                    _,
                    _
                ->
                ProbeResponse(
                    200,
                    "video/mp4",
                    10
                )
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        assertEquals(1, repo.enqueue(listOf(request("1"))).failures.size)
        val first = store.all().single()
        gateway.failEnqueue = false
        assertEquals(1, repo.retry(first.id).queued)
        val retried = store.all().single()
        assertEquals(first.id, retried.id)
        assertNotEquals(first.filename, retried.filename)
        assertEquals(DownloadState.Pending, retried.state)
    }

    @Test fun failedPlatformCancellationKeepsTheActualActiveState() = runTest {
        val store = FakeDownloadStore()
        val gateway = FakeDownloadGateway().apply { failRemove = true }
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight {
                    _,
                    _,
                    _
                ->
                ProbeResponse(
                    200,
                    "video/mp4",
                    10
                )
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        repo.enqueue(listOf(request("1")))
        assertTrue(runCatching { repo.cancel(store.all().single().id) }.isFailure)
        assertEquals(DownloadState.Pending, store.all().single().state)
        assertEquals(1, gateway.snapshots.size)
    }

    @Test fun retryAfterAmbiguousNativeJobsAreRemovedReleasesTheReservation() = runTest {
        val store = FakeDownloadStore()
        val gateway = FakeDownloadGateway()
        val repo = DownloadManagerRepository(
            store,
            gateway,
            MediaPreflight {
                    _,
                    _,
                    _
                ->
                ProbeResponse(
                    200,
                    "video/mp4",
                    10
                )
            },
            clock,
            StandardTestDispatcher(testScheduler)
        )
        repo.enqueue(listOf(request("1")))
        val task = store.all().single()
        store.update(
            task.copy(
                systemId = null,
                state = DownloadState.Failed,
                reasonCode = DownloadReason.Ambiguous
            )
        )
        gateway.snapshots.clear()
        assertEquals(1, repo.retry(task.id).queued)
        assertEquals(DownloadState.Pending, store.all().single().state)
    }
}
