package dev.sctvdl.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import dev.sctvdl.app.features.archive.ArchiveScreen
import dev.sctvdl.app.features.archive.ArchiveUiState
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.DownloadRequest
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class BrowseFlowTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun choosingAnAvailableDateAndDismissingDownloadCreatesNoTask() {
        val latest = BroadcastDate("latest", LocalDate.of(2026, 10, 6))
        val older = BroadcastDate("older", LocalDate.of(2026, 10, 5))
        var state by mutableStateOf(
            ArchiveUiState(
                programmeId = "1",
                programme = Programme("1", "四川新闻联播", null, 0),
                dates = CachedResource(listOf(latest, older)),
                date = latest,
                contents = CachedResource(listOf(ProgrammeContent("clip", "今日新闻片段", standardUrl = "one.mp4")))
            )
        )
        val requests = mutableListOf<DownloadRequest>()
        compose.setContent {
            SctvTheme(AppSettings()) {
                ArchiveScreen(state, false, {}, { state = state.copy(date = it) }, {}, {}, {}, {}, {}, {}, {}, {}, {
                    requests.addAll(it)
                })
            }
        }
        compose.onNodeWithText("2026-10-06").performClick()
        compose.onNodeWithText("10月5日 星期一").performClick()
        compose.runOnIdle { assertEquals("older", state.date?.id) }
        compose.onNodeWithText("下载").performScrollTo().performClick()
        compose.onNodeWithText("选择下载清晰度").assertIsDisplayed()
        compose.onNodeWithContentDescription("关闭清晰度选择").performClick()
        compose.runOnIdle { assertTrue(requests.isEmpty()) }
    }
}
