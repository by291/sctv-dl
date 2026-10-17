package dev.sctvdl.feature.downloads

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import dev.sctvdl.domain.download.DownloadAction
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTarget
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DownloadManagementTest {
    @get:Rule val compose = createComposeRule()

    @Test fun darkLargeTextBatchKeepsCapturedAttemptIdentityUntilConfirmation() {
        val task = DownloadTask(
            "id", "1", "完整节目标题", "栏目", LocalDate.of(2026, 10, 17),
            Quality.Standard, Quality.Standard, "https://fscgc.scgchc.com/a.mp4", "a.mp4", true,
            createdAt = Instant.EPOCH, owner = DownloadOwner.Media3, attemptId = "first", state = DownloadState.Running
        )
        val state = mutableStateOf(DownloadsUiState(listOf(task), loading = false))
        val mutations = mutableListOf<Pair<DownloadAction, List<DownloadTarget>>>()
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                SctvAppTheme(AppSettings(theme = ThemeMode.Dark)) {
                    DownloadsScreen(
                        state.value, {}, {}, {}, {}, {}, {}, {}, {},
                        onBeginSelection = { state.value = state.value.copy(selecting = true) },
                        onSelectAll = { state.value = state.value.copy(selection = mapOf("id" to "first")) },
                        onAction = { action, targets -> mutations += action to targets }
                    )
                }
            }
        }
        compose.onNodeWithText("批量管理").performClick()
        compose.onNodeWithText("全选当前列表").performClick()
        compose.onNodeWithText("取消下载").performClick()
        compose.runOnIdle {
            assertEquals(0, mutations.size)
            state.value = state.value.copy(tasks = listOf(task.copy(attemptId = "replacement")))
        }
        compose.onNodeWithText("确认取消下载").performClick()
        compose.runOnIdle {
            assertEquals(listOf(DownloadAction.Cancel to listOf(DownloadTarget("id", "first"))), mutations)
        }
    }
}
