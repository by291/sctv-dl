package dev.sctvdl.app

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.repository.DownloadRepository
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.domain.testing.MainDispatcherRule
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun preferenceUpdatesReachGlobalPresentation() = runTest {
        val settings = TestSettings()
        val model = AppViewModel(settings, TestDownloads(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        settings.settings.value = AppSettings(theme = ThemeMode.Dark, wifiOnlyDownloads = true)
        runCurrent()
        assertEquals(ThemeMode.Dark, model.uiState.value.settings.theme)
        assertEquals(true, model.uiState.value.settings.wifiOnlyDownloads)
    }

    @Test fun acknowledgingAnOlderOutcomeKeepsTheNewerDownloadMessage() = runTest {
        val downloads = TestDownloads()
        val model = AppViewModel(TestSettings(), downloads, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        model.enqueue(listOf(request()))
        runCurrent()
        val first = requireNotNull(model.uiState.value.downloadMessage)
        model.enqueue(listOf(request()))
        runCurrent()
        val second = requireNotNull(model.uiState.value.downloadMessage)
        model.acknowledgeMessage(first.id)
        runCurrent()
        assertEquals(second, model.uiState.value.downloadMessage)
        assertEquals(2, downloads.submissions)
        model.acknowledgeMessage(second.id)
        runCurrent()
        assertNull(model.uiState.value.downloadMessage)
    }

    @Test fun anEmptySelectionDoesNotSubmitADownload() = runTest {
        val downloads = TestDownloads()
        val model = AppViewModel(TestSettings(), downloads, SavedStateHandle())
        model.enqueue(emptyList())
        runCurrent()
        assertEquals(0, downloads.submissions)
        assertNull(model.uiState.value.downloadMessage)
    }

    @Test fun savedFeedbackSurvivesViewModelRecreation() = runTest {
        val saved = SavedStateHandle(mapOf("downloadMessage" to "Pending outcome", "downloadMessageId" to 7L))
        val model = AppViewModel(TestSettings(), TestDownloads(), saved)
        assertNotNull(model.uiState.value.downloadMessage)
        assertEquals(7L, model.uiState.value.downloadMessage?.id)
    }

    @Test fun reconciliationPropagatesCoroutineCancellation() = runTest {
        val model = AppViewModel(TestSettings(), TestDownloads(cancelReconcile = true), SavedStateHandle())
        var cancelled = false
        try {
            model.reconcile()
        } catch (_: CancellationException) {
            cancelled = true
        }
        assertEquals(true, cancelled)
    }

    private fun request() = DownloadRequest(
        "Programme",
        LocalDate.of(2026, 10, 10),
        ProgrammeContent("1", "Episode", standardUrl = "one.mp4"),
        Quality.Standard,
        false
    )
}

private class TestSettings : SettingsRepository {
    override val settings = MutableStateFlow(AppSettings())

    override suspend fun update(settings: AppSettings) {
        this.settings.value = settings
    }
}

private class TestDownloads(private val cancelReconcile: Boolean = false) : DownloadRepository {
    var submissions = 0

    override fun observeTasks() = MutableStateFlow(emptyList<DownloadTask>())

    override suspend fun enqueue(requests: List<DownloadRequest>): BatchDownloadResult {
        submissions++
        return BatchDownloadResult(requests.size, 0, emptyList())
    }

    override suspend fun cancel(taskId: String) = Unit

    override suspend fun retry(taskId: String) = BatchDownloadResult(1, 0, emptyList())

    override suspend fun removeRecord(taskId: String) = Unit

    override suspend fun reconcile() {
        if (cancelReconcile) throw CancellationException("Cancelled")
    }
}
