package dev.sctvdl.feature.programmes

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.archive.ArchiveScreen
import dev.sctvdl.feature.programmes.archive.ArchiveUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class BrowseFlowTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun choosingAnAvailableDateAndDismissingBatchDownloadCreatesNoTask() {
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
            SctvAppTheme(AppSettings()) {
                ArchiveScreen(
                    state, false, {}, { state = state.copy(date = it) }, {}, {}, {},
                    { state = state.copy(selectionMode = true) }, {}, {},
                    { state = state.copy(selectedIds = setOf(it)) }, {}, { requests.addAll(it) }
                )
            }
        }
        compose.onNodeWithText("更多日期").performClick()
        val dateOption = hasText("10月5日") and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton)
        compose.onNode(dateOption).performClick()
        compose.runOnIdle { assertEquals("older", state.date?.id) }
        compose.onNodeWithText("批量下载").performScrollTo().performClick()
        compose.onNodeWithContentDescription("选择今日新闻片段").performScrollTo().performClick()
        compose.onNodeWithText("下载所选（1）").performClick()
        compose.onNodeWithText("选择下载清晰度").assertIsDisplayed()
        compose.onNodeWithContentDescription("关闭清晰度选择").performClick()
        compose.runOnIdle { assertTrue(requests.isEmpty()) }
    }
}
