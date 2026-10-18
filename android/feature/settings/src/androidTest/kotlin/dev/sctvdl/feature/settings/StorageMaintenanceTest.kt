package dev.sctvdl.feature.settings

import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class StorageMaintenanceTest {
    @get:Rule val compose = createComposeRule()

    @Test fun cacheAndHistoryHaveSeparateConfirmationActions() {
        var cache = 0
        var history = 0
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                SettingsScreen(AppSettings(), {
                }, {}, {}, {}, onClearCache = { cache++ }, onClearHistory = { history++ })
            }
        }
        compose.onNodeWithText("清理缓存").performScrollTo().performClick()
        compose.onNodeWithText("取消").performClick()
        compose.runOnIdle { assertEquals(0, cache) }
        compose.onNodeWithText("清空观看记录").performScrollTo().performClick()
        compose.onNodeWithText("确认清理").performClick()
        compose.runOnIdle {
            assertEquals(0, cache)
            assertEquals(1, history)
        }
    }
}
