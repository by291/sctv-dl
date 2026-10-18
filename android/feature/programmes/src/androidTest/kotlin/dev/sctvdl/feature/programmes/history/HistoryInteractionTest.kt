package dev.sctvdl.feature.programmes.history

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class HistoryInteractionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun searchExitStaysInHistoryAndOpeningKeepsTheLegacyTarget() {
        val target = ViewingTarget.LegacyDownload(
            "legacy-17",
            "Full episode title",
            "Programme",
            LocalDate.of(2026, 10, 17)
        )
        val state =
            mutableStateOf(
                HistoryUiState(listOf(ViewingEntry(target, 12_000, 60_000, Instant.now(), false)), loading = false)
            )
        var backs = 0
        var opened: ViewingTarget? = null
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                HistoryScreen(state.value, {
                    backs++
                }, { opened = it }, { state.value = state.value.copy(query = it) }, {}, {})
            }
        }
        compose.onNodeWithContentDescription("搜索观看记录").performClick()
        compose.onNodeWithText("搜索观看记录").performTextInput("Programme")
        compose.onNodeWithContentDescription("退出搜索").performClick()
        compose.runOnIdle {
            assertEquals(0, backs)
            assertEquals("", state.value.query)
        }
        compose.onNodeWithText("Full episode title").assertIsDisplayed()
        compose.onNodeWithText("继续观看").performClick()
        compose.runOnIdle { assertEquals(target, opened) }
    }
}
