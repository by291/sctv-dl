package dev.sctvdl.feature.programmes.archive

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.domain.testing.MainDispatcherRule
import dev.sctvdl.feature.programmes.archive.ArchiveViewModel
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

    @Test fun clickedProgrammeRemainsVisibleUntilNewMetadataIsAccepted() = runTest {
        val clicked = Programme("1", "Visible programme", "old-cover.jpg", 0)
        val latest = clicked.copy(name = "Updated programme", coverUrl = "new-cover.jpg")
        val repo = FakeProgrammes().apply {
            observeProgrammes().value = CachedResource(listOf(latest))
        }
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        runCurrent()
        model.open("1", clicked)
        runCurrent()
        assertEquals(clicked, model.uiState.value.programme)
        assertTrue(model.uiState.value.hasUpdate)

        model.open("1", latest)
        runCurrent()
        assertEquals(clicked, model.uiState.value.programme)
        model.applyUpdates()
        runCurrent()
        assertEquals(latest, model.uiState.value.programme)
    }

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

        assertEquals("11", model.uiState.value.date?.id)
        assertEquals("Visible clip", model.uiState.value.contents.data?.single()?.title)
        assertEquals(setOf("20"), model.uiState.value.selectedIds)
        assertTrue(model.uiState.value.hasUpdate)
        model.applyUpdates()
        runCurrent()
        assertEquals("11", model.uiState.value.date?.id)
        assertEquals(setOf("20"), model.uiState.value.selectedIds)
        model.exitSelection()
        model.applyUpdates()
        runCurrent()
        assertEquals("10", model.uiState.value.date?.id)
        assertNull(
            "The previous broadcast's pending rows must never enter the new date",
            model.uiState.value.contents.data
        )
        assertTrue(model.uiState.value.selectedIds.isEmpty())
        assertFalse(model.uiState.value.hasUpdate)
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
        assertEquals("10", model.uiState.value.date?.id)
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
        assertEquals("20", model.uiState.value.contents.data?.single()?.id)
        assertTrue(model.uiState.value.hasUpdate)
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
        assertEquals("20", model.uiState.value.contents.data?.single()?.id)
        assertTrue(model.uiState.value.hasUpdate)
        model.applyUpdates()
        runCurrent()
        assertEquals(emptyList<ProgrammeContent>(), model.uiState.value.contents.data)
        assertFalse(model.uiState.value.hasUpdate)
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
        assertEquals("10", model.uiState.value.date?.id)
        assertEquals("30", model.uiState.value.contents.data?.single()?.id)
        assertFalse(model.uiState.value.hasUpdate)
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
        assertEquals("21", model.uiState.value.contents.data?.single()?.id)
        model.open("2")
        repo.observeDates("1").value = CachedResource(listOf(newer))
        runCurrent()
        assertEquals("2", model.uiState.value.programmeId)
        assertNull(model.uiState.value.date)
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
        assertEquals(setOf("21"), model.uiState.value.selectedIds)
        model.selectAll()
        assertEquals(setOf("20", "21"), model.uiState.value.selectedIds)
        model.toggleContent("22")
        assertFalse("22" in model.uiState.value.selectedIds)
        model.selectFullEpisodes()
        assertEquals(setOf("20"), model.uiState.value.selectedIds)
        assertEquals(
            "20",
            archiveDownloadRequests(
                model.uiState.value,
                model.uiState.value.selectedIds,
                Quality.Standard,
                false
            ).single().content.id
        )
        model.selectDate(older)
        runCurrent()
        assertTrue(model.uiState.value.selectedIds.isEmpty())
        assertFalse(model.uiState.value.selectionMode)
    }
}
