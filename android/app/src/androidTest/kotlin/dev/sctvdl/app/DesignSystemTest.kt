package dev.sctvdl.app

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import dev.sctvdl.app.features.settings.SettingsScreen
import dev.sctvdl.design.ContentCard
import dev.sctvdl.design.ProgrammeCard
import dev.sctvdl.design.QualitySheet
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.VideoVariant
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DesignSystemTest {
    @get:Rule val compose = createComposeRule()

    @Test fun wifiSettingExposesItsLabelAndToggleAsOneAccessibleControl() {
        var enabled = false
        compose.setContent {
            SctvTheme(AppSettings()) {
                SettingsScreen(AppSettings(), {}, {}, {}, { enabled = it }, {})
            }
        }
        compose.onNode(hasText("仅 Wi-Fi 下载") and isToggleable()).assertHasClickAction().performClick()
        compose.runOnIdle { assertTrue(enabled) }
    }

    @Test fun batchCheckboxAnnouncesTheProgrammeItSelects() {
        var selected = false
        compose.setContent {
            SctvTheme(AppSettings()) {
                ContentCard(
                    ProgrammeContent("1", "新闻片段", standardUrl = "one.mp4"),
                    false,
                    true,
                    false,
                    {},
                    {},
                    { selected = true }
                )
            }
        }
        compose.onNodeWithContentDescription("选择新闻片段").assertHasClickAction().performClick()
        compose.runOnIdle { assertTrue(selected) }
    }

    @Test fun dismissingQualitySheetDoesNotSelectAQuality() {
        var selected = false
        var dismissed = false
        compose.setContent {
            SctvTheme(AppSettings()) {
                QualitySheet(
                    listOf(
                        VideoVariant(Quality.Standard, "one.mp4"),
                        VideoVariant(Quality.Smooth, "two.mp4")
                    ),
                    1,
                    {
                        selected = true
                    },
                    { dismissed = true }
                )
            }
        }
        compose.onNodeWithContentDescription("关闭清晰度选择").performClick()
        compose.runOnIdle {
            assertTrue(dismissed)
            assertFalse(selected)
        }
    }

    @Test fun longChineseTitleAtTwoHundredPercentKeepsFavouriteActionAccessible() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                SctvTheme(AppSettings()) {
                    ProgrammeCard(Programme("1", "四川新闻联播与天府大地的每一份精彩故事", null, 0), false, {}, {})
                }
            }
        }
        compose.onNodeWithContentDescription(
            "收藏四川新闻联播与天府大地的每一份精彩故事"
        ).assertIsDisplayed().assertHasClickAction()
    }
}
