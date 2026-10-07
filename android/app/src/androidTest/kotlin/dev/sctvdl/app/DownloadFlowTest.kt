package dev.sctvdl.app

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.sctvdl.app.features.downloads.DownloadTab
import dev.sctvdl.app.features.downloads.DownloadsScreen
import dev.sctvdl.app.features.downloads.DownloadsUiState
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.DownloadState
import dev.sctvdl.domain.DownloadTask
import dev.sctvdl.domain.Quality
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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
            SctvTheme(AppSettings()) {
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
        compose.onNodeWithText("已下载 4.0 KiB").assertIsDisplayed()
        compose.onNodeWithText("暂停").assertDoesNotExist()
        compose.onNodeWithText("取消").performClick()
        compose.runOnIdle { assertEquals("task", cancelled) }
    }

    @Test fun failedTransferRemainsVisibleAndOffersRetryInTheActiveSection() {
        var retried: String? = null
        compose.setContent {
            SctvTheme(AppSettings()) {
                DownloadsScreen(
                    DownloadsUiState(listOf(task(DownloadState.Failed)), loading = false),
                    {}, {}, { retried = it }, {}, {}, {}, {}, {}
                )
            }
        }
        compose.onNodeWithText("下载失败").assertIsDisplayed()
        compose.onNodeWithText("重试").performClick()
        compose.runOnIdle { assertEquals("task", retried) }
    }

    @Test fun missingFileOffersRetryAndHistoryRemovalInsteadOfPlayback() {
        var retried = false
        var removed = false
        compose.setContent {
            SctvTheme(AppSettings()) {
                DownloadsScreen(
                    DownloadsUiState(
                        listOf(task(DownloadState.Missing)),
                        DownloadTab.Completed,
                        false
                    ),
                    {
                    }, {}, {
                        retried = true
                    }, { removed = true }, {}, {}, {}, {}
                )
            }
        }
        compose.onNodeWithText("文件已移除").assertIsDisplayed()
        compose.onNodeWithText("本地播放").assertDoesNotExist()
        compose.onNodeWithText("重新下载").performClick()
        compose.onNodeWithText("移除记录").performClick()
        compose.runOnIdle {
            assertTrue(retried)
            assertTrue(removed)
        }
    }
}
