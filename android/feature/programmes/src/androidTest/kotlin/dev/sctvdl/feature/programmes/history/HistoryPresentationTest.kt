package dev.sctvdl.feature.programmes.history

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.InputModeManager
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performKeyInput
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.pressKey
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.programmes.history.components.HistoryCard
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class HistoryPresentationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun unstartedAndCompletedEntriesDoNotShowMisleadingResumeProgress() {
        var entry by mutableStateOf(fixture("one").copy(positionMs = 0))
        var opens = 0
        var removals = 0
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                HistoryCard(entry, { opens++ }, { removals++ })
            }
        }

        compose.onAllNodes(isProgressBar()).assertCountEquals(0)
        compose.onNodeWithText("播放").performClick()
        compose.runOnIdle {
            assertEquals(1, opens)
            entry = entry.copy(positionMs = 60_000, completed = true)
        }
        compose.onAllNodes(isProgressBar()).assertCountEquals(0)
        compose.onNodeWithText("再看一次").performClick()
        compose.onNodeWithContentDescription("更多操作").performClick()
        compose.runOnIdle { assertEquals(0, removals) }
        compose.onNodeWithText("移除观看记录").performClick()
        compose.runOnIdle {
            assertEquals(2, opens)
            assertEquals(1, removals)
        }
        compose.onNodeWithText("Episode one").performClick()
        compose.runOnIdle { assertEquals(3, opens) }
    }

    @Test fun largeTextKeepsFullTitleArtworkProgressAndIndependentActionsInBothThemes() {
        var theme by mutableStateOf(ThemeMode.Light)
        val title = "四川新闻联播：今日重要新闻与精彩节目回看"
        val entry = fixture("long").copy(
            target = ViewingTarget.LegacyDownload("long", title, "四川新闻联播", LocalDate.of(2026, 10, 17)),
            positionMs = 3_723_000,
            durationMs = 7_200_000
        )
        var opens = 0
        var progressColor = Color.Unspecified
        lateinit var inputMode: InputModeManager
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                SctvAppTheme(AppSettings(theme = theme)) {
                    inputMode = LocalInputModeManager.current
                    progressColor = MaterialTheme.colorScheme.primary
                    Box(Modifier.size(320.dp, 900.dp).verticalScroll(rememberScrollState())) {
                        HistoryCard(entry, { opens++ }, {})
                    }
                }
            }
        }
        for (mode in listOf(ThemeMode.Light, ThemeMode.Dark)) {
            compose.runOnIdle { theme = mode }
            val cover = compose.onNodeWithTag("history-cover", useUnmergedTree = true).getUnclippedBoundsInRoot()
            assertEquals(16f / 9f, (cover.right - cover.left) / (cover.bottom - cover.top), .02f)
            val pixels = compose.onNodeWithTag("history-cover", useUnmergedTree = true).captureToImage().toPixelMap()
            val bottomProgress = pixels[pixels.width / 4, pixels.height - 2]
            assertTrue(
                "Progress must be drawn inside the artwork's bottom edge",
                (
                    abs(bottomProgress.red - progressColor.red) +
                        abs(bottomProgress.green - progressColor.green) +
                        abs(bottomProgress.blue - progressColor.blue)
                    ) < .05f
            )
            val layouts = mutableListOf<TextLayoutResult>()
            compose.onNodeWithText(title, useUnmergedTree = true).fetchSemanticsNode()
                .config[SemanticsActions.GetTextLayoutResult].action!!.invoke(layouts)
            assertFalse("Large text must retain the complete programme title", layouts.single().hasVisualOverflow)
            compose.onNodeWithText("看到 1:02:03 / 2:00:00").assertIsDisplayed()
            val action = compose.onNodeWithText("继续观看").performScrollTo()
            compose.runOnIdle { inputMode.requestInputMode(InputMode.Keyboard) }
            action.performSemanticsAction(SemanticsActions.RequestFocus) { it() }
            action.assertIsFocused()
            action.performKeyInput { pressKey(Key.Enter) }
            capture("history-large-${mode.name.lowercase()}")
        }
        compose.runOnIdle { assertEquals(2, opens) }
    }

    @Test fun searchRetainsTheListViewportAndEmptySearchCanBeCleared() {
        val today = LocalDate.now()
        val zone = ZoneId.systemDefault()
        val entries = listOf(
            fixture("today").copy(viewedAt = today.atTime(12, 0).atZone(zone).toInstant()),
            fixture("yesterday").copy(viewedAt = today.minusDays(1).atTime(23, 0).atZone(zone).toInstant()),
            fixture("earlier").copy(viewedAt = today.minusDays(3).atStartOfDay(zone).toInstant())
        )
        var state by mutableStateOf(HistoryUiState(entries, loading = false))
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f)) {
                SctvAppTheme(AppSettings()) {
                    Box(Modifier.size(360.dp, 900.dp)) {
                        HistoryScreen(state, {}, {}, { query ->
                            state = state.copy(
                                query = query,
                                entries = if (query.isEmpty()) entries else emptyList()
                            )
                        }, {}, {})
                    }
                }
            }
        }
        compose.onNodeWithText("今天").assertIsDisplayed()
        compose.onNodeWithText("昨天").assertIsDisplayed()
        compose.onNodeWithText("更早").assertIsDisplayed()
        val before = compose.onNodeWithText("Episode today").getUnclippedBoundsInRoot()
        capture("history-compact")
        compose.onNodeWithContentDescription("搜索观看记录").performClick()
        assertEquals(before, compose.onNodeWithText("Episode today").getUnclippedBoundsInRoot())
        compose.onNodeWithText("搜索观看记录").performTextInput("missing")
        compose.onNodeWithText("清除搜索").performClick()
        compose.runOnIdle { assertTrue(state.query.isEmpty()) }
        compose.onNodeWithText("Episode today").assertIsDisplayed()
    }

    @Test fun cachedHistoryFailureKeepsItsViewportAndRetryAvailable() {
        var state by mutableStateOf(HistoryUiState(listOf(fixture("cached")), loading = false))
        var retries = 0
        var opens = 0
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                HistoryScreen(state, {}, { opens++ }, {}, {}, { retries++ })
            }
        }
        val before = compose.onNodeWithText("Episode cached").getUnclippedBoundsInRoot()

        compose.runOnIdle { state = state.copy(error = "无法读取观看记录，请重试") }
        assertEquals(before, compose.onNodeWithText("Episode cached").getUnclippedBoundsInRoot())
        compose.onNodeWithText("重试").performClick()
        compose.onNodeWithText("重试").performClick()
        compose.onNodeWithText("继续观看").performClick()
        compose.runOnIdle {
            assertEquals(2, retries)
            assertEquals(1, opens)
            state = state.copy(error = null)
        }
        compose.onNodeWithText("无法读取观看记录，请重试").assertDoesNotExist()
    }

    private fun fixture(id: String) = ViewingEntry(
        ViewingTarget.LegacyDownload(id, "Episode $id", "Programme", LocalDate.of(2025, 9, 26)),
        12_000,
        60_000,
        Instant.now(),
        false
    )

    private fun isProgressBar() = SemanticsMatcher.keyIsDefined(SemanticsProperties.ProgressBarRangeInfo)

    private fun capture(name: String) {
        compose.waitForIdle()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
            .executeShellCommand("screencap -p /data/local/tmp/sctv-$name.png")
    }
}
