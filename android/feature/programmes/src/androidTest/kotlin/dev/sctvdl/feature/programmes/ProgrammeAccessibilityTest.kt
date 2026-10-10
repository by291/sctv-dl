package dev.sctvdl.feature.programmes

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.archive.components.EpisodeCard
import dev.sctvdl.feature.programmes.catalogue.components.ProgrammeCard
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ProgrammeAccessibilityTest {
    @get:Rule val compose = createComposeRule()

    @Test fun batchCheckboxAnnouncesTheProgrammeItSelects() {
        var selected = false
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                EpisodeCard(
                    ProgrammeContent("1", "新闻片段", standardUrl = "one.mp4"),
                    false,
                    true,
                    false,
                    {},
                    { selected = true }
                )
            }
        }
        compose.onNodeWithContentDescription("选择新闻片段").assertHasClickAction().performClick()
        compose.runOnIdle { assertTrue(selected) }
    }

    @Test fun longChineseTitleAtTwoHundredPercentKeepsFavouriteActionAccessible() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                SctvAppTheme(AppSettings()) {
                    ProgrammeCard(Programme("1", "四川新闻联播与天府大地的每一份精彩故事", null, 0), false, {}, {})
                }
            }
        }
        compose.onNodeWithContentDescription(
            "收藏四川新闻联播与天府大地的每一份精彩故事"
        ).assertIsDisplayed().assertHasClickAction()
    }
}
