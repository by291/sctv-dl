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
