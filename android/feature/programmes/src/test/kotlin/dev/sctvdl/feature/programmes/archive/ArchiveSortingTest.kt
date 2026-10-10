package dev.sctvdl.feature.programmes.archive

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.domain.testing.MainDispatcherRule
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ArchiveSortingTest {
    @get:Rule val main = MainDispatcherRule()
    private val date = BroadcastDate("broadcast", LocalDate.of(2026, 10, 9))
    private val programme = Programme("1", "四川新闻联播", null, 0)
    private val contents = listOf(
        ProgrammeContent("unknown", "Missing time", standardUrl = "unknown.mp4"),
        ProgrammeContent("later", "Later clip", standardUrl = "later.mp4", publishedAt = "2026-10-09 18:58:29"),
        ProgrammeContent("earlier", "Earlier clip", standardUrl = "earlier.mp4", publishedAt = "2026-10-09 18:40:05"),
        ProgrammeContent("equal", "Equal time", standardUrl = "equal.mp4", publishedAt = "2026-10-09 18:40:05"),
        ProgrammeContent("invalid", "Invalid time", publishedAt = "2026-02-30 12:00:00"),
        ProgrammeContent("full", "四川新闻联播（2026.10.09）", publishedAt = "2026-10-09 18:30:00")
    )

    @Test fun firstEntryOrdersClipsByTimeWithStableTiesAndUnknownTimesLast() = runTest {
        val repo = repository()
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()

        assertEquals(listOf("earlier", "equal", "later", "unknown", "invalid"), model.uiState.value.clips.map { it.id })
        assertEquals(listOf("full"), model.uiState.value.fullEpisodes.map { it.id })
        assertEquals(contents, model.uiState.value.contents.data)
        assertEquals(listOf("unknown", "later", "earlier", "equal", "invalid", "full"), contents.map { it.id })
    }

    @Test fun descendingOrderKeepsUnknownTimesLastAndDoesNotReverseEqualTimes() = runTest {
        val model = ArchiveViewModel(repository(), FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        model.toggleClipSort()

        assertEquals(listOf("later", "earlier", "equal", "unknown", "invalid"), model.uiState.value.clips.map { it.id })
        assertEquals(listOf("full"), model.uiState.value.fullEpisodes.map { it.id })
        model.toggleClipSort()
        assertEquals(listOf("earlier", "equal", "later", "unknown", "invalid"), model.uiState.value.clips.map { it.id })
    }

    @Test fun sortSurvivesDateChangesReturnsAndRestorationButResetsForAnotherProgramme() = runTest {
        val older = BroadcastDate("older", date.date.minusDays(1))
        val repo = repository().apply {
            observeDates("1").value = CachedResource(listOf(date, older))
            observeContents("1", older.id).value = CachedResource(contents.take(4))
            observeDates("2").value = CachedResource(listOf(date))
            observeContents("2", date.id).value = CachedResource(contents.take(4))
        }
        val saved = SavedStateHandle()
        val model = ArchiveViewModel(repo, FakeFavourites(), saved)
        model.open("1")
        runCurrent()
        model.toggleClipSort()
        model.selectDate(older)
        runCurrent()
        model.open("1")
        runCurrent()
        assertEquals(listOf("later", "earlier", "equal", "unknown"), model.uiState.value.clips.map { it.id })

        val restored = ArchiveViewModel(
            repo,
            FakeFavourites(),
            SavedStateHandle(saved.keys().associateWith { saved.get<Any>(it) })
        )
        restored.open("1")
        runCurrent()
        assertEquals("older", restored.uiState.value.date?.id)
        assertEquals(listOf("later", "earlier", "equal", "unknown"), restored.uiState.value.clips.map { it.id })

        restored.open("2")
        runCurrent()
        assertEquals(listOf("earlier", "equal", "later", "unknown"), restored.uiState.value.clips.map { it.id })
    }

    @Test fun sortingUsesAcceptedRowsAndCannotReorderAnActiveSelection() = runTest {
        val repo = repository()
        val model = ArchiveViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.open("1")
        runCurrent()
        model.toggleContent("earlier")
        repo.observeContents("1", date.id).value = CachedResource(
            contents.map { if (it.id == "later") it.copy(publishedAt = "2026-10-09 18:35:00") else it }
        )
        runCurrent()
        model.toggleClipSort()
        model.applyUpdates()

        assertEquals(listOf("earlier", "equal", "later", "unknown", "invalid"), model.uiState.value.clips.map { it.id })
        assertEquals(setOf("earlier"), model.uiState.value.selectedIds)
        assertTrue(model.uiState.value.hasUpdate)
        model.exitSelection()
        model.toggleClipSort()
        assertEquals(listOf("later", "earlier", "equal", "unknown", "invalid"), model.uiState.value.clips.map { it.id })
        model.applyUpdates()
        assertEquals(listOf("earlier", "equal", "later", "unknown", "invalid"), model.uiState.value.clips.map { it.id })
        assertFalse(model.uiState.value.hasUpdate)
    }

    private fun repository() = FakeProgrammes().apply {
        catalogue.value = CachedResource(listOf(programme))
        observeDates("1").value = CachedResource(listOf(date))
        observeContents("1", date.id).value = CachedResource(contents)
    }
}
