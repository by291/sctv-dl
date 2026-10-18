package dev.sctvdl.app

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DownloadFeedbackTest {
    @get:Rule val compose = createComposeRule()

    @Test fun viewingDownloadsFromTheNoticeLeavesPlaybackAndConsumesTheOutcome() {
        var message by mutableStateOf<AppMessage?>(null)
        val consumed = mutableListOf<Long>()
        compose.setContent {
            val snackbar = remember { SnackbarHostState() }
            var downloadsRequest by remember { mutableIntStateOf(0) }
            DownloadFeedback(message, snackbar, { id ->
                consumed += id
                message = null
            }, { downloadsRequest++ })
            SctvAppTheme(AppSettings()) {
                Box(Modifier.fillMaxSize()) {
                    AppNavigationShell(downloadsRequest = downloadsRequest) { route, navigator, _ ->
                        when (route) {
                            AppRoute.Catalogue -> Button(onClick = {
                                navigator.open(AppRoute.Playback("1", "2", "3"))
                            }) { Text("打开播放器") }
                            is AppRoute.Playback -> Button(onClick = {
                                message = AppMessage(7, "已加入下载队列 1 项")
                            }) { Text("提交下载") }
                            AppRoute.Downloads -> Text("下载任务列表")
                            else -> Text("设置页面")
                        }
                    }
                    SnackbarHost(snackbar, Modifier.align(Alignment.Center))
                }
            }
        }

        compose.onNodeWithText("打开播放器").performClick()
        compose.onNodeWithText("提交下载").performClick()
        compose.onNodeWithText("查看下载").performClick()
        compose.onNodeWithText("下载任务列表").assertIsDisplayed()
        compose.onNodeWithText("已加入下载队列 1 项").assertDoesNotExist()
        compose.runOnIdle { assertEquals(listOf(7L), consumed) }

        compose.onNodeWithTag("tab-Settings").performClick()
        compose.onNodeWithText("设置页面").assertIsDisplayed()
    }

    @Test fun anUnclickedNoticeExpiresWithoutNavigatingAndAcknowledgesOnlyItsOwnOutcome() {
        var message by mutableStateOf<AppMessage?>(AppMessage(1, "第一个下载结果"))
        val consumed = mutableListOf<Long>()
        var opened = 0
        compose.setContent {
            val snackbar = remember { SnackbarHostState() }
            DownloadFeedback(message, snackbar, { consumed += it }, { opened++ })
            SctvAppTheme(AppSettings()) { SnackbarHost(snackbar) }
        }
        compose.onNodeWithText("第一个下载结果").assertIsDisplayed()
        compose.runOnIdle { message = AppMessage(2, "最新下载结果") }
        compose.onNodeWithText("最新下载结果").assertIsDisplayed()
        compose.mainClock.advanceTimeBy(10_000)
        compose.waitForIdle()

        compose.onNodeWithText("最新下载结果").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(0, opened)
            assertEquals(listOf(2L), consumed)
        }
    }
}
