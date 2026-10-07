package dev.sctvdl.app.features

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.app.MainDispatcherRule
import dev.sctvdl.app.features.downloads.DownloadTab
import dev.sctvdl.app.features.downloads.DownloadsViewModel
import dev.sctvdl.app.features.downloads.batchResultMessage
import dev.sctvdl.app.features.downloads.downloadProgress
import dev.sctvdl.app.features.downloads.downloadStatus
import dev.sctvdl.app.features.player.LocalPlayerViewModel
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.BatchDownloadResult
import dev.sctvdl.domain.DownloadFailure
import dev.sctvdl.domain.DownloadRepository
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.DownloadState
import dev.sctvdl.domain.DownloadTask
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.Quality
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

fun fixtureTask(state: DownloadState, id: String = "task") = DownloadTask(
    id,
    "1",
    "四川新闻联播",
    "四川新闻联播",
    LocalDate.of(
        2026,
        10,
        6
    ),
    Quality.Standard,
    Quality.Standard,
    "https://fscgc.scgchc.com/a.mp4",
    "safe.mp4",
    true,
    systemId = 1,
    contentUri = if (state == DownloadState.Completed) "content://downloads/1" else null,
    bytes = 4096,
    state = state,
    createdAt = Instant.EPOCH
)

class FakeDownloads : DownloadRepository {
    val tasks = MutableStateFlow(emptyList<DownloadTask>())
    val cancelled = mutableListOf<String>()
    val retried = mutableListOf<String>()
    val removed = mutableListOf<String>()
    var markMissing = false
    override fun observeTasks() = tasks
    override suspend fun enqueue(requests: List<DownloadRequest>) = BatchDownloadResult(
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
    override suspend fun cancel(taskId: String) {
        cancelled.add(taskId)
    }
    override suspend fun retry(taskId: String): BatchDownloadResult {
        retried.add(taskId)
        return BatchDownloadResult(1, 0, emptyList())
    }
    override suspend fun removeRecord(taskId: String) {
        removed.add(taskId)
    }
    override suspend fun reconcile() {
        if (markMissing) tasks.value = tasks.value.map { it.copy(state = DownloadState.Missing) }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class DownloadsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun failedTransfersStayInTheRecoverySectionAfterTheStateChanges() = runTest {
        val repo = FakeDownloads().apply { tasks.value = listOf(fixtureTask(DownloadState.Running)) }
        val model = DownloadsViewModel(repo, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()
        repo.tasks.value = listOf(fixtureTask(DownloadState.Failed))
        runCurrent()
        assertEquals(listOf("task"), model.state.value.visible.map { it.id })
        assertEquals("下载失败", downloadStatus(model.state.value.visible.single()))
        model.tab(DownloadTab.Completed)
        runCurrent()
        assertTrue(model.state.value.visible.isEmpty())
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
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()
        assertEquals(listOf("task"), model.state.value.visible.map { it.id })
        assertEquals("正在下载", downloadStatus(model.state.value.visible.single()))
        assertEquals("已下载 4.0 KiB", downloadProgress(model.state.value.visible.single()))
        model.tab(DownloadTab.Completed)
        runCurrent()
        assertEquals(listOf("complete", "missing"), model.state.value.visible.map { it.id })
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

    @Test fun aDeletedLocalFileCannotProduceAPlaybackSource() = runTest {
        val repo = FakeDownloads().apply {
            tasks.value = listOf(fixtureTask(DownloadState.Completed))
            markMissing = true
        }
        val model = LocalPlayerViewModel(repo, SavedStateHandle())
        model.open("task")
        runCurrent()
        assertNull(model.state.value.source)
        assertEquals(ErrorKind.Storage, model.state.value.error?.kind)
        assertFalse(model.state.value.loading)
    }
}
