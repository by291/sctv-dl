package dev.sctvdl.app

import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class NavigationTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun settingsAndDownloadsArePrimaryDestinationsAndSelectionRestores() {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity(::showPrimaryRoutes)
            requireNotNull(device.wait(Until.findObject(By.res("tab-Downloads")), 5_000)).click()
            assertNotNull(device.wait(Until.findObject(By.text("页面 Downloads")), 5_000))
            requireNotNull(device.wait(Until.findObject(By.res("tab-Settings")), 5_000)).click()
            assertNotNull(device.wait(Until.findObject(By.text("页面 Settings")), 5_000))
            scenario.recreate()
            scenario.onActivity(::showPrimaryRoutes)
            assertNotNull(device.wait(Until.findObject(By.text("页面 Settings")), 5_000))
        }
    }

    private fun showPrimaryRoutes(activity: ComponentActivity) {
        activity.setContent {
            SctvAppTheme(AppSettings()) {
                Box(Modifier.semantics { testTagsAsResourceId = true }) {
                    AppNavigationShell { route, _ -> Text("页面 ${route::class.simpleName}") }
                }
            }
        }
    }

    @Test fun archiveHidesPrimaryNavigationAndBackRestoresCatalogue() {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            AppNavigationShell { route, navigator ->
                                when (route) {
                                    AppRoute.Catalogue -> Button(onClick = { navigator.open(AppRoute.Archive("1")) }) {
                                        Text("打开栏目")
                                    }
                                    is AppRoute.Archive -> Button(onClick = navigator.back) { Text("返回节目库") }
                                    else -> Text("页面 ${route::class.simpleName}")
                                }
                            }
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("打开栏目")), 5_000)).click()
            assertNotNull(device.wait(Until.findObject(By.text("返回节目库")), 5_000))
            device.waitForIdle()
            assertNull(device.findObject(By.res("tab-Catalogue")))
            requireNotNull(device.findObject(By.text("返回节目库"))).click()
            assertNotNull(device.wait(Until.findObject(By.res("tab-Catalogue")), 5_000))
        }
    }

    @Test fun downloadNotificationOpensDownloadsFromASecondaryDestination() {
        var request by mutableIntStateOf(0)
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            AppNavigationShell(downloadsRequest = request) { route, navigator ->
                                Column {
                                    Text("页面 ${route::class.simpleName}")
                                    Button(onClick = { navigator.open(AppRoute.Archive("1")) }) { Text("打开栏目") }
                                }
                            }
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("打开栏目")), 5_000)).click()
            assertNotNull(device.wait(Until.findObject(By.text("页面 Archive")), 5_000))
            scenario.onActivity { request++ }
            assertNotNull(device.wait(Until.findObject(By.text("页面 Downloads")), 5_000))
        }
    }

    @Test fun notificationIntentDoesNotOverrideTheRestoredDestination() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java).putExtra("open_downloads", true)
        ActivityScenario.launch<MainActivity>(intent).use { scenario ->
            assertNotNull(device.wait(Until.findObject(By.text("进行中 · 0")), 5_000))
            requireNotNull(device.wait(Until.findObject(By.res("tab-Settings")), 5_000)).click()
            assertNotNull(device.wait(Until.findObject(By.text("显示模式")), 5_000))
            scenario.recreate()
            assertNotNull(device.wait(Until.findObject(By.text("显示模式")), 5_000))
        }
    }
}
