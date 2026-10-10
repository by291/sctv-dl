package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryExplorationTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val programmes = listOf(Programme("one", "Alpha", null, 0), Programme("two", "Beta", null, 1))

    @Test fun firstLoadKeepsExplorationVisibleWithoutPullingTheListBackToTheTop() {
        var state by mutableStateOf(CatalogueUiState(resource = CachedResource(isRefreshing = true)))
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        CatalogueScreen(state, false, {}, {}, {}, {}, {}, {})
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.desc("正在加载栏目")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                state = state.copy(
                    resource = CachedResource(
                        programmes + (2 until 40).map { Programme("$it", "Programme $it", null, it) }
                    )
                )
            }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
            scenario.onActivity { state = state.copy(featuredId = "one") }
            val exploration = device.wait(Until.findObject(By.desc("查看栏目Alpha")), 5_000)
            assertNotNull("The first loaded exploration action must be visible without scrolling", exploration)
            val tabs = requireNotNull(device.findObject(By.text("全部栏目")))
            assertTrue(exploration!!.visibleBounds.top >= tabs.visibleBounds.bottom)
        }
    }

    @Test fun explorationOpensTheProgrammeCurrentlyDisplayedAfterChanging() {
        var state by mutableStateOf(CatalogueUiState(resource = CachedResource(programmes), featuredId = "one"))
        var opened: String? = null
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        CatalogueScreen(state, false, {}, {}, {}, {}, { opened = it }, {}, {
                            state = state.copy(featuredId = "two")
                        })
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.desc("换一个栏目")), 5_000)).click()
            requireNotNull(device.wait(Until.findObject(By.desc("查看栏目Beta")), 5_000)).click()
            scenario.onActivity { assertEquals("two", opened) }
        }
    }

    @Test fun searchingAndFavouritesKeepTheExplorationOutOfFilteredResults() {
        var state by mutableStateOf(CatalogueUiState(resource = CachedResource(programmes), featuredId = "one"))
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            CatalogueScreen(
                                state,
                                state.favouritesOnly,
                                { state = state.copy(query = it) },
                                {},
                                {},
                                {},
                                {},
                                { state = state.copy(favouritesOnly = it) }
                            )
                        }
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.res("programme-spotlight")), 5_000))
            requireNotNull(device.wait(Until.findObject(By.desc("搜索栏目")), 5_000)).click()
            requireNotNull(device.findObject(By.clazz("android.widget.EditText"))).text = "Alpha"
            device.wait(Until.gone(By.res("programme-spotlight")), 5_000)
            assertNull(device.findObject(By.res("programme-spotlight")))
            requireNotNull(device.findObject(By.desc("清除搜索"))).click()
            assertNotNull(device.wait(Until.findObject(By.res("programme-spotlight")), 5_000))
            requireNotNull(device.wait(Until.findObject(By.res("filter-favourites")), 5_000)).click()
            device.wait(Until.gone(By.res("programme-spotlight")), 5_000)
            assertNull(device.findObject(By.res("programme-spotlight")))
        }
    }

    @Test fun narrowDarkLibraryAtTwoHundredPercentKeepsExplorationActionsReachable() {
        val programme = Programme("one", "四川新闻联播与天府大地的每一份精彩故事", null, 0)
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    val density = LocalDensity.current
                    CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                        SctvAppTheme(AppSettings(theme = ThemeMode.Dark)) {
                            Box(Modifier.width(320.dp).fillMaxHeight()) {
                                CatalogueScreen(
                                    CatalogueUiState(resource = CachedResource(listOf(programme)), featuredId = "one"),
                                    false,
                                    {},
                                    {},
                                    {},
                                    {},
                                    {},
                                    {}
                                )
                            }
                        }
                    }
                }
            }
            var open: UiObject2? = null
            repeat(8) {
                if (open == null) {
                    device.waitForIdle()
                    open = device.findObject(By.desc("查看栏目四川新闻联播与天府大地的每一份精彩故事"))
                    if (open == null) device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.5f)
                }
            }
            assertNotNull("Exploration action must remain reachable at 200% text", open)
        }
    }
}
