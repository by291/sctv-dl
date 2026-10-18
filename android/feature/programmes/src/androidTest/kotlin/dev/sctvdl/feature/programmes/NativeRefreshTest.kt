package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.archive.ArchiveScreen
import dev.sctvdl.feature.programmes.archive.ArchiveUiState
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeRefreshTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun toolbarSearchOpensAboveTheCatalogueFilterAndClosesWithoutLeavingAQuery() {
        var state by mutableStateOf(
            CatalogueUiState(resource = CachedResource(listOf(Programme("one", "Alpha", null, 0))))
        )
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
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
            val filter = requireNotNull(device.findObject(By.desc("只看收藏")))
            assertTrue(
                "Search belongs above the library filters",
                search!!.visibleBounds.bottom <= filter.visibleBounds.top
            )
            search.text = "missing"
            assertNotNull(device.wait(Until.findObject(By.text("没有匹配的栏目")), 5_000))
            requireNotNull(device.wait(Until.findObject(By.desc("退出搜索")), 5_000)).click()
            device.wait(Until.gone(By.clazz("android.widget.EditText")), 5_000)
            assertNull(device.findObject(By.clazz("android.widget.EditText")))
            scenario.onActivity { assertEquals("", state.query) }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
        }
    }

    @Test fun libraryGesturesDoNotRefreshOrShowACachedLoadingIndicator() {
        val programmes = (0 until 20).map { Programme("$it", if (it == 0) "Alpha" else "Programme $it", null, it) }
        var state by mutableStateOf(CatalogueUiState(resource = CachedResource(programmes, isRefreshing = true)))
        var refreshes = 0
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        CatalogueScreen(state, false, {}, {}, {
                            refreshes++
                            state = state.copy(resource = state.resource.copy(isRefreshing = true))
                        }, {}, {}, {})
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
            device.waitForIdle()
            assertNull(device.findObject(By.clazz("android.widget.ProgressBar")))
            pullDown()
            scenario.onActivity { assertEquals("Scrolling must not refresh the library", 0, refreshes) }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
            pullDown()
            scenario.onActivity {
                assertEquals("Scrolling must not submit a refresh", 0, refreshes)
                state = state.copy(resource = state.resource.copy(isRefreshing = false))
            }
            device.wait(Until.gone(By.clazz("android.widget.ProgressBar")), 5_000)
        }
    }

    @Test fun archiveGesturesDoNotRefreshWithOrWithoutSelection() {
        val date = BroadcastDate("date", LocalDate.of(2026, 10, 8))
        var state by mutableStateOf(
            ArchiveUiState(
                programmeId = "one",
                programme = Programme("one", "Alpha", null, 0),
                date = date,
                dates = CachedResource(listOf(date), isRefreshing = true),
                contents = CachedResource(
                    (0 until 20).map {
                        ProgrammeContent("$it", "News $it", standardUrl = "one.mp4")
                    },
                    isRefreshing = true
                )
            )
        )
        var refreshes = 0
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        ArchiveScreen(state, false, {}, {}, { refreshes++ }, {}, {}, {}, {}, {}, {}, {}, {})
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
            device.waitForIdle()
            assertNull(device.findObject(By.clazz("android.widget.ProgressBar")))
            pullDown()
            scenario.onActivity {
                assertEquals("Scrolling must not refresh the archive", 0, refreshes)
                assertEquals("date", state.date?.id)
                state = state.copy(selectionMode = true)
            }
            assertNotNull(device.wait(Until.findObject(By.text("全选")), 5_000))
            pullDown()
            scenario.onActivity { assertEquals("Batch selection must not trigger a refresh", 0, refreshes) }
        }
    }

    @Test fun uncachedBroadcastUsesNoninteractiveSkeletonsWhenDatesAreCached() {
        val date = BroadcastDate("date", LocalDate.of(2026, 10, 8))
        val state = ArchiveUiState(
            programmeId = "one",
            programme = Programme("one", "Alpha", null, 0),
            date = date,
            dates = CachedResource(listOf(date)),
            contents = CachedResource(isRefreshing = true)
        )
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            ArchiveScreen(state, false, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
                        }
                    }
                }
            }
            val placeholder = device.wait(Until.findObject(By.res("archive-content-placeholder")), 5_000)
            assertNotNull("An uncached broadcast must preserve the content structure", placeholder)
            assertTrue(!placeholder!!.isClickable)
            device.waitForIdle()
            assertEquals(
                "Skeletons must not also show a loading spinner",
                0,
                device.findObjects(By.clazz("android.widget.ProgressBar")).size
            )
        }
    }

    @Test fun failedDateAndContentRefreshOfferOneRetryForThePage() {
        val date = BroadcastDate("date", LocalDate.of(2026, 10, 8))
        val error = AppError(ErrorKind.Network, "Fixture connection failure")
        val state = ArchiveUiState(
            programmeId = "one",
            programme = Programme("one", "Alpha", null, 0),
            date = date,
            dates = CachedResource(listOf(date), error = error),
            contents = CachedResource(emptyList(), error = error)
        )
        var refreshes = 0
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        ArchiveScreen(state, false, {}, {}, { refreshes++ }, {}, {}, {}, {}, {}, {}, {}, {})
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.text("这一天暂无节目")), 5_000))
            assertEquals(
                "One retry must cover both requests and the cached empty state",
                1,
                device.findObjects(By.text("重新连接")).size + device.findObjects(By.text("重试")).size
            )
            requireNotNull(device.findObject(By.text("重新连接"))).click()
            scenario.onActivity { assertEquals(1, refreshes) }
        }
    }

    private fun pullDown() {
        val list = requireNotNull(device.wait(Until.findObject(By.scrollable(true)), 5_000))
        val bounds = list.visibleBounds
        device.swipe(bounds.centerX(), bounds.top + 30, bounds.centerX(), bounds.bottom - 30, 45)
        device.waitForIdle()
    }
}
