package dev.sctvdl.feature.downloads

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.downloads.components.DownloadCard
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DownloadPresentationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun largeTextKeepsArtworkCompactAndFileActionsAboveTheCompleteTitle() {
        val task = task(DownloadState.Completed)
        var played: String? = null
        var shared: String? = null
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                SctvAppTheme(AppSettings(theme = ThemeMode.Dark)) {
                    Box(Modifier.width(320.dp).fillMaxHeight().testTag("viewport")) {
                        Column(Modifier.verticalScroll(rememberScrollState())) {
                            DownloadCard(task, { played = it }, { shared = it.id }, {}, {}, false, false, {}, false)
                        }
                    }
                }
            }
        }

        val cover = compose.onNodeWithTag("download-cover-id").fetchSemanticsNode().boundsInRoot
        val title = compose.onNodeWithText(task.title).fetchSemanticsNode().boundsInRoot
        val menu = compose.onNodeWithContentDescription("文件操作").fetchSemanticsNode().boundsInRoot
        val viewport = compose.onNodeWithTag("viewport").fetchSemanticsNode().boundsInRoot
        assertTrue(cover.width < viewport.width / 2)
        assertTrue(menu.bottom <= title.top)
        assertTrue(cover.bottom <= title.top)
        assertTrue(menu.right <= viewport.right)
        compose.onNodeWithText("4.0 KiB / 8.0 KiB").assertDoesNotExist()
        compose.onNodeWithText("仅 Wi-Fi 下载").assertDoesNotExist()
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)).assertCountEquals(0)
        captureScreenshot("sctv-downloads-large-dark")

        compose.onNodeWithText("播放").performScrollTo().performClick()
        compose.onNodeWithContentDescription("文件操作").performScrollTo().performClick()
        compose.onNodeWithText("分享视频").performClick()

        compose.runOnIdle {
            assertEquals("id", played)
            assertEquals("id", shared)
        }
    }

    @Test fun removedFilesKeepRetryWithoutTransferBytesOrAnErrorMessage() {
        val task = task(DownloadState.Missing).copy(reason = "The public file was deleted")
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadCard(task, {}, {}, {}, {}, false, false, {}, false)
            }
        }

        compose.onNodeWithText("文件已移除").assertIsDisplayed()
        compose.onNodeWithText("重新下载").assertIsDisplayed()
        compose.onNodeWithText("4.0 KiB / 8.0 KiB").assertDoesNotExist()
        compose.onNodeWithText(task.reason!!).assertDoesNotExist()
        compose.onNodeWithText("播放").assertDoesNotExist()
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)).assertCountEquals(0)
    }

    @Test fun failedPublicationRetriesSavingWithoutOfferingAnotherTransfer() {
        val task = task(DownloadState.Failed).copy(cacheComplete = true, reason = "空间不足")
        var action: DownloadAction? = null
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadCard(task, {}, {}, {}, { action = it }, false, false, {}, false)
            }
        }

        compose.onNodeWithText("重新下载").assertDoesNotExist()
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)).assertCountEquals(0)
        compose.onNodeWithText("重试保存").performClick()

        compose.runOnIdle { assertEquals(DownloadAction.Publish, action) }
    }

    @Test fun unavailableListsKeepTheHeaderAndDisableSelectionWhileAllowingReload() {
        val state = mutableStateOf(DownloadsUiState())
        var reloads = 0
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadsScreen(state.value, {}, {}, {}, {}, {}, {}, {}, {}, onReload = { reloads++ })
            }
        }

        compose.onNodeWithText("下载").assertIsDisplayed()
        compose.onNodeWithContentDescription("批量管理").assertIsNotEnabled()
        compose.runOnIdle { state.value = DownloadsUiState(loading = false) }
        compose.onNodeWithText("下载").assertIsDisplayed()
        compose.onNodeWithContentDescription("批量管理").assertIsNotEnabled()
        compose.runOnIdle { state.value = DownloadsUiState(loading = false, error = "Storage unavailable") }
        compose.onNodeWithText("下载").assertIsDisplayed()
        compose.onNodeWithContentDescription("批量管理").assertIsNotEnabled()
        compose.onNodeWithText("重试").performClick()
        compose.runOnIdle { assertEquals(1, reloads) }
    }

    @Test fun activeTasksAppearAboveCompletedTasksInTheGroupedList() {
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadsScreen(
                    DownloadsUiState(
                        tasks = listOf(
                            task(DownloadState.Missing).copy(id = "missing"),
                            task(DownloadState.Completed).copy(id = "complete"),
                            task(DownloadState.Running).copy(id = "running")
                        ),
                        tab = DownloadTab.All,
                        loading = false
                    ),
                    {}, {}, {}, {}, {}, {}, {}, {}
                )
            }
        }

        compose.onNodeWithText("下载中 · 1").assertIsDisplayed()
        val active = compose.onNodeWithText("下载中 · 1").fetchSemanticsNode().boundsInRoot
        val completed = compose.onNodeWithText("已完成 · 1").fetchSemanticsNode().boundsInRoot
        assertTrue(active.bottom < completed.top)
        captureScreenshot("sctv-downloads-grouped-light")
        compose.onNodeWithText("已完成 · 1").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("已移除 · 1").performScrollTo().assertIsDisplayed()
    }

    @Test fun longPressSelectsThePresentedAttemptWithoutAddingAnOrdinaryCardAction() {
        val task = task(DownloadState.Running).copy(attemptId = "presented")
        val state = mutableStateOf(DownloadsUiState(tasks = listOf(task), loading = false))
        val actions = mutableListOf<Pair<DownloadAction, List<DownloadTarget>>>()
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadsScreen(
                    state.value, {}, {}, {}, {}, {}, {}, {}, {},
                    onBeginSelection = { state.value = state.value.copy(selecting = true) },
                    onToggle = { selected ->
                        state.value = state.value.copy(selection = mapOf(selected.id to selected.attemptId))
                    },
                    onAction = { action, targets -> actions += action to targets }
                )
            }
        }

        compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.OnLongClick)).assertHasNoClickAction()
        compose.onNodeWithText(task.title).performTouchInput { longClick() }
        compose.onNodeWithText("已选择 1 项").assertIsDisplayed()
        compose.onNodeWithText("批量操作").performClick()
        compose.onNodeWithText("暂停 · 1").performClick()

        compose.runOnIdle {
            assertEquals(listOf(DownloadAction.Pause to listOf(DownloadTarget("id", "presented"))), actions)
        }
    }

    private fun captureScreenshot(name: String) {
        compose.waitForIdle()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            .executeShellCommand("screencap -p /data/local/tmp/$name.png")
    }

    private fun task(state: DownloadState): DownloadTask {
        val date = LocalDate.of(2026, 10, 17)
        val title = "市场监管总局启动智慧计量监管试点，持续提升公共服务质量"
        return DownloadTask(
            "id", "1", title, "现场快报", date,
            Quality.Standard, Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "a.mp4", true,
            contentUri = "content://downloads/1".takeIf { state == DownloadState.Completed },
            bytes = 4096,
            totalBytes = 8192,
            state = state,
            createdAt = Instant.EPOCH,
            owner = DownloadOwner.Media3,
            selection = ProgrammeSelection(
                Programme("1", "现场快报", null, 0),
                BroadcastDate("date", date),
                ProgrammeContent("1", title)
            )
        )
    }
}
