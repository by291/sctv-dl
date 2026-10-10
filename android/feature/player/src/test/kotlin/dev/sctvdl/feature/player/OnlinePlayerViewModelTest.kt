package dev.sctvdl.feature.player

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.domain.testing.MainDispatcherRule
import dev.sctvdl.feature.player.OnlinePlayerViewModel
import dev.sctvdl.feature.player.PlaybackSelection
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OnlinePlayerViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val settings = object : SettingsRepository {
        override val settings = MutableStateFlow(AppSettings(initialQuality = Quality.Smooth))

        override suspend fun update(settings: AppSettings) {
            this.settings.value = settings
        }
    }

    @Test fun backgroundArchiveUpdatesDoNotReplaceAnOpenedSource() = runTest {
        val repo = FakeProgrammes().apply {
            observeContents("1", "10").value = CachedResource(
                listOf(ProgrammeContent("100", "Accepted clip", standardUrl = "accepted.mp4"))
            )
        }
        val model = OnlinePlayerViewModel(repo, settings, SavedStateHandle())
        model.open("1", "10", "100")
        runCurrent()
        repo.observeContents("1", "10").value = CachedResource(emptyList())
        runCurrent()

        assertEquals("Accepted clip", model.uiState.value.source?.title)
        assertEquals("accepted.mp4", model.uiState.value.content?.standardUrl)
    }

    @Test fun displayedArchiveSelectionWinsOverNewerRepositoryRows() = runTest {
        val repo = FakeProgrammes().apply { observeContents("1", "10").value = CachedResource(emptyList()) }
        val model = OnlinePlayerViewModel(repo, settings, SavedStateHandle())
        model.open(
            "1",
            "10",
            "100",
            PlaybackSelection(
                "1",
                "10",
                ProgrammeContent("100", "Accepted clip", standardUrl = "accepted.mp4"),
                "Accepted programme",
                LocalDate.of(2026, 10, 8)
            )
        )
        runCurrent()
        assertEquals("Accepted clip", model.uiState.value.source?.title)
        assertEquals("accepted.mp4", model.uiState.value.content?.standardUrl)
        assertEquals("Accepted programme", model.uiState.value.programmeName)
        assertEquals(LocalDate.of(2026, 10, 8), model.uiState.value.broadcastDate)
        assertFalse(model.uiState.value.loading)
        assertNull(model.uiState.value.error)
    }

    @Test fun displayedSelectionCannotLeakIntoAnotherPlaybackKey() = runTest {
        val repo = FakeProgrammes().apply {
            observeContents("1", "11").value =
                CachedResource(listOf(ProgrammeContent("101", "Current clip", standardUrl = "new.mp4")))
        }
        val model = OnlinePlayerViewModel(repo, settings, SavedStateHandle())
        model.open(
            "1",
            "11",
            "101",
            PlaybackSelection(
                "1",
                "10",
                ProgrammeContent("100", "Previous clip", standardUrl = "old.mp4"),
                "Previous programme",
                LocalDate.of(2026, 10, 8)
            )
        )
        runCurrent()
        assertEquals("Current clip", model.uiState.value.source?.title)
        assertEquals("new.mp4", model.uiState.value.content?.standardUrl)
    }

    @Test fun currentContentAndSavedPositionWinOverLateArchiveResponses() = runTest {
        val repo = FakeProgrammes()
        val saved = SavedStateHandle(mapOf("positionMs" to 8000L))
        val model = OnlinePlayerViewModel(repo, settings, saved)
        model.open("1", "10", "100")
        model.open("1", "11", "101")
        repo.observeContents(
            "1",
            "11"
        ).value = CachedResource(
            listOf(
                ProgrammeContent(
                    "101",
                    "current",
                    standardUrl = "one.mp4",
                    smoothUrl = "two.mp4"
                )
            )
        )
        repo.observeContents(
            "1",
            "10"
        ).value = CachedResource(
            listOf(
                ProgrammeContent(
                    "100",
                    "late",
                    standardUrl = "old.mp4"
                )
            )
        )
        runCurrent()
        assertEquals("101", model.uiState.value.source?.id)
        assertEquals(8000L, model.uiState.value.source?.startPositionMs)
        assertEquals(Quality.Smooth, model.uiState.value.initialQuality)
        model.savePosition(12000)
        assertEquals(12000L, saved.get<Long>("positionMs"))
    }

    @Test fun missingMediaProducesARecoverableError() = runTest {
        val repo = FakeProgrammes().apply {
            observeContents(
                "1",
                "10"
            ).value = CachedResource(
                listOf(
                    ProgrammeContent(
                        "100",
                        "文本"
                    )
                )
            )
        }
        val model = OnlinePlayerViewModel(repo, settings, SavedStateHandle())
        model.open("1", "10", "100")
        runCurrent()
        assertEquals(ErrorKind.NoVideo, model.uiState.value.error?.kind)
        assertFalse(model.uiState.value.loading)
    }
}
