package dev.sctvdl.feature.programmes

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.repository.ProgrammeRepository
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.domain.testing.MainDispatcherRule
import dev.sctvdl.feature.programmes.archive.ArchiveViewModel
import dev.sctvdl.feature.programmes.catalogue.CatalogueViewModel
import java.io.IOException
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ObservationRecoveryTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun catalogueRetryResubscribesWithoutAcceptingPendingReplacementRows() = runTest {
        val rows = listOf(Programme("1", "Accepted", null, 0))
        val source = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        var fail = true
        val repository = object : ProgrammeRepository by source {
            override fun observeProgrammes() = flow {
                emit(source.catalogue.value)
                if (fail) throw IOException("Database read failed")
                emitAll(source.catalogue)
            }
        }
        val model = CatalogueViewModel(repository, FakeFavourites(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        assertEquals(rows, model.uiState.value.resource.data)
        assertNotNull(model.uiState.value.resource.error)

        fail = false
        source.catalogue.value = CachedResource(listOf(Programme("2", "Pending", null, 0)))
        model.refresh()
        runCurrent()

        assertEquals(rows, model.uiState.value.resource.data)
        assertNull(model.uiState.value.resource.error)
        assertTrue(model.uiState.value.hasUpdate)
    }

    @Test fun archiveRetryRestartsTheFailedDateSubscriptionAndRetainsItsSelection() = runTest {
        val date = BroadcastDate("2", LocalDate.of(2026, 10, 18))
        val source = FakeProgrammes().apply { observeDates("1").value = CachedResource(listOf(date)) }
        var fail = true
        val repository = object : ProgrammeRepository by source {
            override fun observeDates(programmeId: String) = flow {
                emit(source.observeDates(programmeId).value)
                if (fail) throw IOException("Database read failed")
                emitAll(source.observeDates(programmeId))
            }
        }
        val model = ArchiveViewModel(repository, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()

        assertEquals(date, model.uiState.value.date)
        assertNotNull(model.uiState.value.dates.error)

        fail = false
        model.refresh()
        runCurrent()

        assertEquals(date, model.uiState.value.date)
        assertNull(model.uiState.value.dates.error)
    }

    @Test fun archiveContentAndContextFailuresRecoverWithoutAcceptingPendingMetadata() = runTest {
        val programme = Programme("1", "Accepted", null, 0)
        val date = BroadcastDate("2", LocalDate.of(2026, 10, 18))
        val content = ProgrammeContent("3", "Accepted clip", standardUrl = "clip.mp4")
        val source = FakeProgrammes().apply {
            catalogue.value = CachedResource(listOf(programme))
            observeDates("1").value = CachedResource(listOf(date))
            observeContents("1", "2").value = CachedResource(listOf(content))
        }
        var fail = true
        val repository = object : ProgrammeRepository by source {
            override fun observeProgrammes() = flow {
                emit(source.catalogue.value)
                if (fail) throw IOException("Context failed")
                emitAll(source.catalogue)
            }

            override fun observeContents(programmeId: String, dateId: String) = flow {
                emit(source.observeContents(programmeId, dateId).value)
                if (fail) throw IOException("Contents failed")
                emitAll(source.observeContents(programmeId, dateId))
            }
        }
        val model = ArchiveViewModel(repository, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()

        assertEquals(programme, model.uiState.value.programme)
        assertEquals(listOf(content), model.uiState.value.contents.data)
        assertNotNull(model.uiState.value.contextError)
        assertNotNull(model.uiState.value.contents.error)

        fail = false
        source.catalogue.value = CachedResource(listOf(programme.copy(name = "Pending")))
        source.observeContents("1", "2").value = CachedResource(listOf(content.copy(title = "Pending clip")))
        model.refresh()
        runCurrent()

        assertEquals(programme, model.uiState.value.programme)
        assertEquals(listOf(content), model.uiState.value.contents.data)
        assertNull(model.uiState.value.contextError)
        assertNull(model.uiState.value.contents.error)
        assertTrue(model.uiState.value.hasUpdate)
    }

    @Test fun aCancelledDatesObserverCannotReportFailureIntoAnotherProgramme() = runTest {
        val currentDate = BroadcastDate("20", LocalDate.of(2026, 10, 18))
        val source = FakeProgrammes().apply { observeDates("2").value = CachedResource(listOf(currentDate)) }
        val repository = object : ProgrammeRepository by source {
            override fun observeDates(programmeId: String) = flow {
                if (programmeId == "1") {
                    try {
                        awaitCancellation()
                    } finally {
                        // A database failure can race cancellation after navigation has selected another key.
                        throw IOException("Old observer failed while closing")
                    }
                } else {
                    emitAll(source.observeDates(programmeId))
                }
            }
        }
        val model = ArchiveViewModel(repository, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()

        model.open("2")
        runCurrent()

        assertEquals("2", model.uiState.value.programmeId)
        assertEquals(currentDate, model.uiState.value.date)
        assertNull(model.uiState.value.dates.error)
    }
}
