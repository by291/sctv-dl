package dev.sctvdl.ui

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.downloads.DownloadQualitySheet
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class DownloadQualitySheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun dismissingQualitySheetDoesNotSelectAQuality() {
        var selected = false
        var dismissed = false
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                DownloadQualitySheet(
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
}
