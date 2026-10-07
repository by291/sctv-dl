package dev.sctvdl.app

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import org.junit.Rule
import org.junit.Test

class NavigationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun primaryDestinationsAndTopLevelSelectionRestore() {
        val restore = StateRestorationTester(compose)
        restore.setContent {
            SctvTheme(AppSettings()) {
                AppNavigationShell { route, _ ->
                    androidx.compose.material3.Text("页面 ${route::class.simpleName}")
                }
            }
        }
        compose.onNodeWithTag("tab-Downloads").performClick()
        compose.onNodeWithText("页面 Downloads").assertIsDisplayed()
        restore.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("页面 Downloads").assertIsDisplayed()
        compose.onNodeWithTag("tab-Favourites").performClick()
        compose.onNodeWithText("页面 Favourites").assertIsDisplayed()
        compose.onNodeWithTag("tab-Catalogue").performClick()
        compose.onNodeWithText("页面 Catalogue").assertIsDisplayed()
    }
}
