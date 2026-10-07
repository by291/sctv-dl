package dev.sctvdl.app.features

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.app.FakeProgrammes
import dev.sctvdl.app.MainDispatcherRule
import dev.sctvdl.app.features.player.PlayerViewModel
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.SettingsRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PlayerViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val settings = object : SettingsRepository {
        override val settings = MutableStateFlow(AppSettings(initialQuality = Quality.Smooth))
        override suspend fun update(settings: AppSettings) {
            this.settings.value = settings
        }
    }

    @Test fun currentContentAndSavedPositionWinOverLateArchiveResponses() = runTest {
        val repo = FakeProgrammes()
        val saved = SavedStateHandle(mapOf("positionMs" to 8000L))
        val model = PlayerViewModel(repo, settings, saved)
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
        assertEquals("101", model.state.value.source?.id)
        assertEquals(8000L, model.state.value.source?.startPositionMs)
        assertEquals(Quality.Smooth, model.state.value.initialQuality)
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
        val model = PlayerViewModel(repo, settings, SavedStateHandle())
        model.open("1", "10", "100")
        runCurrent()
        assertEquals(ErrorKind.NoVideo, model.state.value.error?.kind)
        assertFalse(model.state.value.loading)
    }
}
