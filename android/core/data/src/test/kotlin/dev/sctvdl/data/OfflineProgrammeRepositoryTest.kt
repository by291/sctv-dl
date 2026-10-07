package dev.sctvdl.data

import dev.sctvdl.data.network.UpstreamParser
import dev.sctvdl.data.repository.OfflineProgrammeRepository
import dev.sctvdl.data.repository.ProgrammeSource
import dev.sctvdl.data.repository.SnapshotStore
import dev.sctvdl.data.repository.StoredSnapshot
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.ErrorKind
import java.io.IOException
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OfflineProgrammeRepositoryTest {
    private class Store : SnapshotStore {
        private val values = mutableMapOf<String, MutableStateFlow<StoredSnapshot?>>()
        override fun observe(key: String) = values.getOrPut(key) { MutableStateFlow(null) }
        override suspend fun put(snapshot: StoredSnapshot) {
            observe(snapshot.key).value = snapshot
        }
    }
    private class Source : ProgrammeSource {
        var response = """{"rs":200,"data":[]}"""
        var failure = false
        var slow = CompletableDeferred<Unit>()
        override suspend fun programmes() = """{"rs":200,"data":{"records":[]}}"""
        override suspend fun dates(programmeId: String): String {
            if (failure) throw IOException("offline")
            return response
        }
        override suspend fun contents(programmeId: String, dateId: String): String {
            if (dateId == "1") slow.await()
            return """{"rs":200,"data":[{"id":"$dateId","title":"$dateId"}]}"""
        }
    }
    private val clock = Clock.fixed(Instant.parse("2026-10-07T00:00:00Z"), ZoneOffset.UTC)

    @Test fun successfulEmptySnapshotSurvivesRepositoryRecreation() = runTest {
        val store = Store()
        val source = Source()
        val dispatcher = StandardTestDispatcher(testScheduler)
        val first = OfflineProgrammeRepository(source, store, UpstreamParser(), clock, dispatcher)
        first.refreshDates("1")
        val restored =
            OfflineProgrammeRepository(source, store, UpstreamParser(), clock, dispatcher)
        val value = restored.observeDates("1").first()
        assertEquals(emptyList<BroadcastDate>(), value.data)
        assertEquals(clock.instant(), value.updatedAt)
    }

    @Test fun failedRefreshKeepsSuccessfulDataAndReportsTheError() = runTest {
        val source = Source().apply {
            response =
                """{"rs":200,"data":[{"id":"3","date":"2026-10-06"}]}"""
        }
        val repo =
            OfflineProgrammeRepository(
                source,
                Store(),
                UpstreamParser(),
                clock,
                StandardTestDispatcher(testScheduler)
            )
        repo.refreshDates("1")
        source.failure = true
        repo.refreshDates("1")
        val value = repo.observeDates("1").first()
        assertEquals("3", value.data?.single()?.id)
        assertEquals(ErrorKind.Network, value.error?.kind)
        assertFalse(value.isRefreshing)
    }

    @Test fun delayedArchiveCannotOverwriteAnotherDateKey() = runTest {
        val source = Source()
        val repo =
            OfflineProgrammeRepository(
                source,
                Store(),
                UpstreamParser(),
                clock,
                StandardTestDispatcher(testScheduler)
            )
        val slow = launch { repo.refreshContents("1", "1") }
        runCurrent()
        repo.refreshContents("1", "2")
        source.slow.complete(Unit)
        slow.join()
        assertEquals("2", repo.observeContents("1", "2").first().data?.single()?.id)
        assertEquals("1", repo.observeContents("1", "1").first().data?.single()?.id)
    }

    @Test fun cancellationIsRethrownAndRefreshingFlagIsCleared() = runTest {
        val repo =
            OfflineProgrammeRepository(
                Source(),
                Store(),
                UpstreamParser(),
                clock,
                StandardTestDispatcher(testScheduler)
            )
        val job = launch { repo.refreshContents("1", "1") }
        runCurrent()
        job.cancelAndJoin()
        val value = repo.observeContents("1", "1").first()
        assertNull(value.error)
        assertFalse(value.isRefreshing)
    }
}
