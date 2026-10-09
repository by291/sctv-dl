package dev.sctvdl.app.features

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.app.FakeFavourites
import dev.sctvdl.app.FakeProgrammes
import dev.sctvdl.app.MainDispatcherRule
import dev.sctvdl.app.features.archive.ArchiveViewModel
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.Quality
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ArchiveViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val older = BroadcastDate("10", LocalDate.of(2026, 10, 5))
    private val newer = BroadcastDate("11", LocalDate.of(2026, 10, 6))

    @Test fun backgroundResultsKeepTheVisibleDateAndSelectedContents() = runTest {
        val repo = FakeProgrammes().apply {
            observeDates("1").value = CachedResource(listOf(newer, older))
            observeContents("1", "11").value = CachedResource(
                listOf(ProgrammeContent("20", "Visible clip", standardUrl = "old.mp4"))
            )
        }
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        model.toggleContent("20")

        repo.observeDates("1").value = CachedResource(listOf(older))
        repo.observeContents("1", "11").value = CachedResource(emptyList())
        runCurrent()

        assertEquals("11", model.state.value.date?.id)
        assertEquals("Visible clip", model.state.value.contents.data?.single()?.title)
        assertEquals(setOf("20"), model.state.value.selectedIds)
        assertTrue(model.state.value.hasUpdate)
        model.applyUpdates()
        runCurrent()
        assertEquals("11", model.state.value.date?.id)
        assertEquals(setOf("20"), model.state.value.selectedIds)
        model.exitSelection()
        model.applyUpdates()
        runCurrent()
        assertEquals("10", model.state.value.date?.id)
        assertNull(
            "The previous broadcast's pending rows must never enter the new date",
            model.state.value.contents.data
        )
        assertTrue(model.state.value.selectedIds.isEmpty())
        assertFalse(model.state.value.hasUpdate)
    }

    @Test fun returningToTheSameArchiveRefreshesWithoutResettingItsDate() = runTest {
        val repo = FakeProgrammes().apply { observeDates("1").value = CachedResource(listOf(newer, older)) }
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        model.selectDate(older)
        runCurrent()
        model.open("1")
        runCurrent()

        assertEquals(listOf("1", "1"), repo.dateRequests)
        assertEquals(listOf("1" to "11", "1" to "10", "1" to "10"), repo.contentRequests)
        assertEquals("10", model.state.value.date?.id)
    }

    @Test fun returningDuringActiveRequestsDoesNotSubmitDuplicatesOrAcceptPendingRows() = runTest {
        val gate = CompletableDeferred<Unit>()
        val repo = FakeProgrammes().apply {
            dateRefreshGate = gate
            contentRefreshGate = gate
            observeDates("1").value = CachedResource(listOf(newer))
            observeContents("1", "11").value = CachedResource(listOf(ProgrammeContent("20", "Visible clip")))
        }
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        repo.observeContents("1", "11").value = CachedResource(listOf(ProgrammeContent("21", "Pending clip")))
        runCurrent()
        model.open("1")
        model.refresh()
        runCurrent()
        assertEquals(listOf("1"), repo.dateRequests)
        assertEquals(listOf("1" to "11"), repo.contentRequests)
        assertEquals("20", model.state.value.contents.data?.single()?.id)
        assertTrue(model.state.value.hasUpdate)
        gate.complete(Unit)
        runCurrent()
    }

    @Test fun acceptingChangedContentsUsesTheNewestResultWithoutAnotherRequest() = runTest {
        val repo = FakeProgrammes().apply {
            observeDates("1").value = CachedResource(listOf(newer))
            observeContents("1", "11").value = CachedResource(listOf(ProgrammeContent("20", "Visible clip")))
        }
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        repo.observeContents("1", "11").value = CachedResource(listOf(ProgrammeContent("21", "New clip")))
        runCurrent()
        repo.observeContents("1", "11").value = CachedResource(emptyList())
        runCurrent()
        assertEquals("20", model.state.value.contents.data?.single()?.id)
        assertTrue(model.state.value.hasUpdate)
        model.applyUpdates()
        runCurrent()
        assertEquals(emptyList<ProgrammeContent>(), model.state.value.contents.data)
        assertFalse(model.state.value.hasUpdate)
        assertEquals(listOf("1" to "11"), repo.contentRequests)
    }

    @Test fun switchingDatesDiscardsPendingRowsFromThePreviousBroadcast() = runTest {
        val repo = FakeProgrammes().apply {
            observeDates("1").value = CachedResource(listOf(newer, older))
            observeContents("1", "11").value = CachedResource(listOf(ProgrammeContent("20", "Visible clip")))
            observeContents("1", "10").value = CachedResource(listOf(ProgrammeContent("30", "Other date")))
        }
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        repo.observeContents("1", "11").value = CachedResource(listOf(ProgrammeContent("21", "Pending clip")))
        runCurrent()
        model.selectDate(older)
        runCurrent()
        model.applyUpdates()
        runCurrent()
        assertEquals("10", model.state.value.date?.id)
        assertEquals("30", model.state.value.contents.data?.single()?.id)
        assertFalse(model.state.value.hasUpdate)
    }

    @Test fun requestsOnlyReturnedDateIdsAndRejectsLateProgrammeOrDateUpdates() = runTest {
        val repo = FakeProgrammes()
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        assertTrue(repo.contentRequests.isEmpty())
        repo.observeDates("1").value = CachedResource(listOf(newer, older))
        runCurrent()
        assertEquals("1" to "11", repo.contentRequests.single())
        model.selectDate(older)
        runCurrent()
        repo.observeContents("1", "11").value =
            CachedResource(listOf(ProgrammeContent("20", "late")))
        repo.observeContents("1", "10").value =
            CachedResource(listOf(ProgrammeContent("21", "current")))
        runCurrent()
        assertEquals("21", model.state.value.contents.data?.single()?.id)
        model.open("2")
        repo.observeDates("1").value = CachedResource(listOf(newer))
        runCurrent()
        assertEquals("2", model.state.value.programmeId)
        assertNull(model.state.value.date)
    }

    @Test fun selectionRestoresForTheSameArchiveAndClearsWhenItsKeyChanges() = runTest {
        val repo = FakeProgrammes().apply {
            catalogue.value = CachedResource(listOf(Programme("1", "四川新闻联播", null, 0)))
            observeDates("1").value = CachedResource(listOf(newer, older))
            observeContents("1", "11").value =
                CachedResource(
                    listOf(
                        ProgrammeContent("20", "四川新闻联播（2026.10.06）", standardUrl = "full.mp4"),
                        ProgrammeContent("21", "片段", smoothUrl = "clip.mp4"),
                        ProgrammeContent("22", "纯文本")
                    )
                )
        }
        val saved = SavedStateHandle(
            mapOf(
                "programmeId" to "1",
                "dateId" to "11",
                "selectedIds" to arrayListOf("21"),
                "selectionMode" to true
            )
        )
        val model = ArchiveViewModel(repo, FakeFavourites(), saved)
        model.open("1")
        runCurrent()
        assertEquals(setOf("21"), model.state.value.selectedIds)
        model.selectAll()
        assertEquals(setOf("20", "21"), model.state.value.selectedIds)
        model.toggleContent("22")
        assertFalse("22" in model.state.value.selectedIds)
        model.selectFullEpisodes()
        assertEquals(setOf("20"), model.state.value.selectedIds)
        assertEquals("20", model.downloadRequests(Quality.Standard, false).single().content.id)
        model.selectDate(older)
        runCurrent()
        assertTrue(model.state.value.selectedIds.isEmpty())
        assertFalse(model.state.value.selectionMode)
    }
}
