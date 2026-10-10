package dev.sctvdl.feature.player.local

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.testing.FakeDownloads
import dev.sctvdl.domain.testing.MainDispatcherRule
import dev.sctvdl.domain.testing.fixtureTask
import dev.sctvdl.feature.player.local.LocalPlayerViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LocalPlayerViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun aDeletedLocalFileCannotProduceAPlaybackSource() = runTest {
        val repo = FakeDownloads().apply {
            tasks.value = listOf(fixtureTask(DownloadState.Completed))
            markMissing = true
        }
        val model = LocalPlayerViewModel(repo, SavedStateHandle())
        model.open("task")
        runCurrent()
        assertNull(model.uiState.value.source)
        assertEquals(ErrorKind.Storage, model.uiState.value.error?.kind)
        assertFalse(model.uiState.value.loading)
    }
}
