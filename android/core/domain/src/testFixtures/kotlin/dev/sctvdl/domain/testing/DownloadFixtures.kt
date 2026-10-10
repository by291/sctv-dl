package dev.sctvdl.domain.testing

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.download.BatchDownloadResult
import dev.sctvdl.domain.download.DownloadFailure
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.repository.DownloadRepository
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map

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
