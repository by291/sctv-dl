package dev.sctvdl.feature.settings

import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.performClick
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.settings.SettingsScreen
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class SettingsAccessibilityTest {
    @get:Rule val compose = createComposeRule()

    @Test fun wifiSettingExposesItsLabelAndToggleAsOneAccessibleControl() {
        var enabled = false
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                SettingsScreen(AppSettings(), {}, {}, {}, { enabled = it })
            }
        }
        compose.onNode(hasText("仅 Wi-Fi 下载") and isToggleable()).assertHasClickAction().performClick()
        compose.runOnIdle { assertTrue(enabled) }
    }
}
