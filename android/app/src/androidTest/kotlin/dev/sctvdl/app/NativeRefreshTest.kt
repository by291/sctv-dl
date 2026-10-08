package dev.sctvdl.app

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.features.archive.ArchiveScreen
import dev.sctvdl.app.features.archive.ArchiveUiState
import dev.sctvdl.app.features.catalogue.CatalogueScreen
import dev.sctvdl.app.features.catalogue.CatalogueUiState
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeRefreshTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun toolbarSearchOpensAboveTheTabsAndClosesWithoutLeavingAFilter() {
        var state by mutableStateOf(
            CatalogueUiState(resource = CachedResource(listOf(Programme("one", "Alpha", null, 0))))
        )
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvTheme(AppSettings()) {
                        CatalogueScreen(state, false, { state = state.copy(query = it) }, {}, {}, {}, {}, {})
                    }
                }
            }
            device.waitForIdle()
            assertNull(
                "Search must not occupy the scrolling library",
                device.findObject(By.clazz("android.widget.EditText"))
            )
            requireNotNull(device.wait(Until.findObject(By.desc("搜索栏目")), 5_000)).click()
            val search = device.wait(Until.findObject(By.clazz("android.widget.EditText")), 5_000)
            assertNotNull(search)
            val tabs = requireNotNull(device.findObject(By.text("全部栏目")))
            assertTrue("Search belongs above the library tabs", search!!.visibleBounds.bottom <= tabs.visibleBounds.top)
            search.text = "missing"
            assertNotNull(device.wait(Until.findObject(By.text("没有匹配的栏目")), 5_000))
            requireNotNull(device.wait(Until.findObject(By.desc("退出搜索")), 5_000)).click()
            device.wait(Until.gone(By.clazz("android.widget.EditText")), 5_000)
            assertNull(device.findObject(By.clazz("android.widget.EditText")))
            scenario.onActivity { assertEquals("", state.query) }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
        }
    }

    @Test fun libraryPullRefreshRetainsCachedResultsAndIgnoresPullsWhileRefreshing() {
        val programmes = (0 until 20).map { Programme("$it", if (it == 0) "Alpha" else "Programme $it", null, it) }
        var state by mutableStateOf(CatalogueUiState(resource = CachedResource(programmes)))
        var refreshes = 0
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvTheme(AppSettings()) {
                        CatalogueScreen(state, false, {}, {}, {
                            refreshes++
                            state = state.copy(resource = state.resource.copy(isRefreshing = true))
                        }, {}, {}, {})
                    }
                }
            }
            pullDown()
            scenario.onActivity { assertEquals("Pulling at the beginning must refresh the library", 1, refreshes) }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
            pullDown()
            scenario.onActivity { assertEquals("An active refresh must not be submitted twice", 1, refreshes) }
        }
    }

    @Test fun archivePullRefreshKeepsTheBroadcastAndIsDisabledDuringSelection() {
        val date = BroadcastDate("date", LocalDate.of(2026, 10, 8))
        var state by mutableStateOf(
            ArchiveUiState(
                programmeId = "one",
                programme = Programme("one", "Alpha", null, 0),
                date = date,
                dates = CachedResource(listOf(date)),
                contents = CachedResource(
                    (0 until 20).map {
                        ProgrammeContent("$it", "News $it", standardUrl = "one.mp4")
                    }
                )
            )
        )
        var refreshes = 0
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvTheme(AppSettings()) {
                        ArchiveScreen(state, false, {}, {}, { refreshes++ }, {}, {}, {}, {}, {}, {}, {}, {})
                    }
                }
            }
            pullDown()
            scenario.onActivity {
                assertEquals("Pulling at the beginning must refresh the archive", 1, refreshes)
                assertEquals("date", state.date?.id)
                state = state.copy(selectionMode = true)
            }
            assertNotNull(device.wait(Until.findObject(By.text("全选")), 5_000))
            pullDown()
            scenario.onActivity { assertEquals("Batch selection must not trigger a refresh", 1, refreshes) }
        }
    }

    private fun pullDown() {
        val list = requireNotNull(device.wait(Until.findObject(By.scrollable(true)), 5_000))
        val bounds = list.visibleBounds
        device.swipe(bounds.centerX(), bounds.top + 30, bounds.centerX(), bounds.bottom - 30, 45)
        device.waitForIdle()
    }
}
