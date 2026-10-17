package dev.sctvdl.feature.downloads

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadFailure
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.testing.FakeDownloads
import dev.sctvdl.domain.testing.MainDispatcherRule
import dev.sctvdl.domain.testing.fixtureTask
import dev.sctvdl.feature.downloads.DownloadTab
import dev.sctvdl.feature.downloads.DownloadsViewModel
import dev.sctvdl.feature.downloads.downloadProgress
import dev.sctvdl.feature.downloads.downloadStatus
import dev.sctvdl.ui.downloads.batchResultMessage
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DownloadsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun failedTransfersMoveIntoTheUnfinishedFilterAfterTheStateChanges() = runTest {
        val repo = FakeDownloads().apply { tasks.value = listOf(fixtureTask(DownloadState.Running)) }
        val model = DownloadsViewModel(repo, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        repo.tasks.value = listOf(fixtureTask(DownloadState.Failed))
        runCurrent()
        assertTrue(model.uiState.value.visible.isEmpty())
        model.tab(DownloadTab.Unfinished)
        runCurrent()
        assertEquals(listOf("task"), model.uiState.value.visible.map { it.id })
        assertEquals("下载失败", downloadStatus(model.uiState.value.visible.single()))
        model.tab(DownloadTab.Completed)
        runCurrent()
        assertTrue(model.uiState.value.visible.isEmpty())
    }

    @Test fun actualStatesUnknownLengthAndActionsRemainTruthful() = runTest {
        val repo = FakeDownloads().apply {
            tasks.value = listOf(
                fixtureTask(DownloadState.Running),
                fixtureTask(
                    DownloadState.Completed,
                    "complete"
                ),
                fixtureTask(
                    DownloadState.Missing,
                    "missing"
                )
            )
        }
        val model = DownloadsViewModel(repo, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertEquals(listOf("task"), model.uiState.value.visible.map { it.id })
        assertEquals("正在下载", downloadStatus(model.uiState.value.visible.single()))
        assertEquals("已下载 4.0 KiB", downloadProgress(model.uiState.value.visible.single()))
        model.tab(DownloadTab.Completed)
        runCurrent()
        assertEquals(listOf("complete"), model.uiState.value.visible.map { it.id })
        model.tab(DownloadTab.Removed)
        runCurrent()
        assertEquals(listOf("missing"), model.uiState.value.visible.map { it.id })
        model.cancel("task")
        model.retry("missing")
        model.remove("complete")
        runCurrent()
        assertEquals(listOf("task"), repo.cancelled)
        assertEquals(listOf("missing"), repo.retried)
        assertEquals(listOf("complete"), repo.removed)
        assertTrue(
            batchResultMessage(
                BatchDownloadResult(
                    1,
                    1,
                    listOf(
                        DownloadFailure(
                            "2",
                            AppError(
                                ErrorKind.Http,
                                "暂不可用"
                            )
                        )
                    )
                )
            ).contains("1 个使用可用清晰度")
        )
    }
}
