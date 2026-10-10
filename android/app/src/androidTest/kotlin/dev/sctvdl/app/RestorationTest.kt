package dev.sctvdl.app

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Rule
import org.junit.Test

class RestorationTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun archiveEntryStateSurvivesTopLevelSwitchAndRecreation() {
        val restore = StateRestorationTester(compose)
        restore.setContent {
            SctvAppTheme(AppSettings()) {
                AppNavigationShell { route, navigator, _ ->
                    when (route) {
                        AppRoute.Catalogue -> Button(onClick = { navigator.open(AppRoute.Archive("1")) }) {
                            Text("打开栏目")
                        }
                        is AppRoute.Archive -> {
                            var selection by rememberSaveable { mutableIntStateOf(0) }
                            Column {
                                Text("选择 $selection")
                                Button(onClick = { selection++ }) { Text("增加选择") }
                                Button(onClick = { navigator.open(AppRoute.Downloads) }) { Text("查看下载") }
                            }
                        }
                        else -> Text("其他页面")
                    }
                }
            }
        }
        compose.onNodeWithText("打开栏目").performClick()
        compose.onNodeWithText("增加选择").performClick()
        compose.onNodeWithText("查看下载").performClick()
        compose.onNodeWithTag("tab-Catalogue").performClick()
        compose.onNodeWithText("选择 1").assertIsDisplayed()
        restore.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("选择 1").assertIsDisplayed()
    }
}
