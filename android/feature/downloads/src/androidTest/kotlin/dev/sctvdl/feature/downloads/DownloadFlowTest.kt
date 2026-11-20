package dev.sctvdl.feature.downloads

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DownloadFlowTest {
    @get:Rule val compose = createComposeRule()

    private fun task(state: DownloadState, total: Long? = null) = DownloadTask(
        "task", "1", "四川新闻联播", "四川新闻联播",
        LocalDate.of(
            2026,
            10,
            6
        ),
        Quality.Standard, Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "safe.mp4", true,
        contentUri = if (state == DownloadState.Completed) {
            "content://downloads/1"
        } else {
            null
        },
        bytes = 4096, totalBytes = total, state = state, createdAt = Instant.EPOCH
    )

    @Test fun unknownLengthShowsBytesAndCancellationHasNoPauseAction() {
        var cancelled: String? = null
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadsScreen(
                    DownloadsUiState(
                        listOf(task(DownloadState.Running)),
                        loading = false
                    ),
                    {
                    }, {
                        cancelled = it
                    }, {}, {}, {}, {}, {}, {}
                )
            }
        }
        compose.onNodeWithText("4.0 KiB · 大小未知").assertIsDisplayed()
        compose.onNodeWithText("暂停").assertDoesNotExist()
        compose.onNodeWithText("取消下载").performClick()
        compose.runOnIdle { assertEquals(null, cancelled) }
        compose.onNodeWithText("确认取消下载").performClick()
        compose.runOnIdle { assertEquals("task", cancelled) }
    }

    @Test fun failedTransferOffersRetryInTheUnfinishedSection() {
        var retried: String? = null
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadsScreen(
                    DownloadsUiState(listOf(task(DownloadState.Failed)), DownloadTab.Unfinished, loading = false),
                    {}, {}, { retried = it }, {}, {}, {}, {}, {}
                )
            }
        }
        compose.onNodeWithText("下载失败").assertIsDisplayed()
        compose.onNodeWithText("重新下载").performClick()
        compose.runOnIdle { assertEquals("task", retried) }
    }

    @Test fun missingFileOffersRetryAndHistoryRemovalInsteadOfPlayback() {
        val deletionReason = "The public file was deleted"
        val missing = task(DownloadState.Missing, total = 8192).copy(reason = deletionReason)
        var retried: String? = null
        var removed: String? = null
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadsScreen(
                    state = DownloadsUiState(
                        tasks = listOf(missing),
                        tab = DownloadTab.Removed,
                        loading = false
                    ),
                    onTab = {},
                    onCancel = {},
                    onRetry = { retried = it },
                    onRemove = { removed = it },
                    onPlay = {},
                    onShare = {},
                    onOpenFile = {},
                    onSystemDownloads = {}
                )
            }
        }

        compose.onNodeWithText("文件已移除").assertIsDisplayed()
        compose.onNodeWithText("播放").assertDoesNotExist()
        compose.onNodeWithText("4.0 KiB / 8.0 KiB").assertDoesNotExist()
        compose.onNodeWithText(deletionReason).assertDoesNotExist()
        val progress = SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)
        compose.onAllNodes(progress).assertCountEquals(0)

        compose.onNodeWithText("重新下载").performClick()
        compose.onNodeWithContentDescription("文件操作").performClick()
        compose.onNodeWithText("移除记录").performClick()
        compose.onNodeWithText("确认移除记录").performClick()
        compose.runOnIdle {
            assertEquals(missing.id, retried)
            assertEquals(missing.id, removed)
        }
    }
}
