package dev.sctvdl.feature.programmes

import android.graphics.Color
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.feature.programmes.archive.ArchiveScreen
import dev.sctvdl.feature.programmes.archive.ArchiveViewModel
import dev.sctvdl.feature.programmes.archive.components.EpisodeCard
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ArchiveSortingTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val date = BroadcastDate("broadcast", LocalDate.of(2026, 10, 9))
    private val earlier = ProgrammeContent(
        "earlier",
        "Earlier clip",
        standardUrl = "earlier.mp4",
        publishedAt = "2026-10-09 18:40:05"
    )
    private val later = ProgrammeContent(
        "later",
        "Later clip",
        standardUrl = "later.mp4",
        publishedAt = "2026-10-09 18:58:29"
    )

    @Test fun iconTogglesVisibleOrderWithoutChangingPlaybackOrActiveSelection() {
        lateinit var model: ArchiveViewModel
        var played: ProgrammeContent? = null
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                model = ArchiveViewModel(repository(), FakeFavourites(), SavedStateHandle())
                model.open("1")
                activity.setContent {
                    val state by model.uiState.collectAsStateWithLifecycle()
                    SctvAppTheme(AppSettings(theme = ThemeMode.Light)) {
                        ArchiveScreen(
                            state, false, {}, model::selectDate, model::refresh, model::toggleFavourite,
                            { played = it }, model::beginSelection, model::selectAll, model::selectFullEpisodes,
                            model::toggleContent, model::exitSelection, {}, onToggleClipSort = model::toggleClipSort
                        )
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.textContains("18:40:05")), 5_000))
            assertOrder("Earlier clip", "Later clip")
            assertSortIconDirection(ascending = true)
            sortButton("切换为时间降序").click()
            assertNotNull(device.wait(Until.findObject(By.desc("切换为时间升序")), 5_000))
            assertOrder("Later clip", "Earlier clip")
            assertSortIconDirection(ascending = false)
            requireNotNull(device.findObject(By.desc("播放节目：Later clip"))).click()
            scenario.onActivity { assertEquals(later, played) }
            sortButton("切换为时间升序").click()
            assertNotNull(device.wait(Until.findObject(By.desc("切换为时间降序")), 5_000))
            assertOrder("Earlier clip", "Later clip")

            requireNotNull(device.findObject(By.text("批量下载"))).click()
            assertNotNull(device.wait(Until.findObject(By.text("全选")), 5_000))
            val disabledSort = sortButton("切换为时间降序")
            assertFalse(disabledSort.isEnabled)
            disabledSort.click()
            requireNotNull(device.findObject(By.desc("选择Earlier clip"))).click()
            assertNotNull(device.wait(Until.findObject(By.text("已选 1 个")), 5_000))
            scenario.onActivity {
                assertTrue(model.uiState.value.clipSortAscending)
                assertEquals(setOf("earlier"), model.uiState.value.selectedIds)
            }
        }
    }

    @Test fun fullEpisodeHidesPublicationTimeInBothPlaybackAndSelectionLayouts() {
        val full = earlier.copy(id = "full", title = "News (2026.10.09)", publishedAt = "2026-10-09 18:30:00")
        var selection by mutableStateOf(false)
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Column {
                            EpisodeCard(full, true, selection, false, {}, {}, date.date)
                            EpisodeCard(earlier, false, selection, false, {}, {}, date.date)
                        }
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.textContains("18:40:05")), 5_000))
            assertNotNull(device.findObject(By.desc("播放节目：News (2026.10.09)")))
            assertNull(device.findObject(By.textContains("18:30:00")))
            scenario.onActivity { selection = true }
            assertNotNull(device.wait(Until.findObject(By.desc("选择News (2026.10.09)")), 5_000))
            assertNotNull(device.findObject(By.textContains("18:40:05")))
            assertNull(device.findObject(By.textContains("18:30:00")))
        }
    }

    @Test fun narrowDarkLargeTextKeepsTimeAndKeyboardSortingReachable() {
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val model = ArchiveViewModel(repository(), FakeFavourites(), SavedStateHandle())
                model.open("1")
                activity.setContent {
                    val state by model.uiState.collectAsStateWithLifecycle()
                    CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                        Box(Modifier.requiredSize(320.dp, 740.dp)) {
                            SctvAppTheme(AppSettings(theme = ThemeMode.Dark)) {
                                Surface {
                                    ArchiveScreen(
                                        state, false, {}, model::selectDate, model::refresh, model::toggleFavourite, {},
                                        model::beginSelection, model::selectAll, model::selectFullEpisodes,
                                        model::toggleContent, model::exitSelection, {},
                                        onToggleClipSort = model::toggleClipSort
                                    )
                                }
                            }
                        }
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.desc("切换为时间降序")), 5_000))
            requireNotNull(device.findObject(By.scrollable(true))).scroll(Direction.DOWN, 0.5f)
            val button = sortButton("切换为时间降序")
            assertTrue(
                "The sort touch target must be at least 48dp: ${button.visibleBounds}",
                button.visibleBounds.width() >= 48 && button.visibleBounds.height() >= 48
            )
            assertNotNull(device.wait(Until.findObject(By.textContains("18:40:05")), 5_000))
            repeat(12) {
                if (!button.isFocused) device.pressKeyCode(KeyEvent.KEYCODE_TAB)
            }
            assertTrue("The sort action must participate in keyboard focus traversal", button.isFocused)
            device.pressKeyCode(KeyEvent.KEYCODE_ENTER)
            assertNotNull(device.wait(Until.findObject(By.desc("切换为时间升序")), 5_000))
            assertOrder("Later clip", "Earlier clip")
        }
    }

    private fun assertOrder(first: String, second: String) {
        val firstCard = requireNotNull(device.findObject(By.desc("播放节目：$first")))
        val secondCard = requireNotNull(device.findObject(By.desc("播放节目：$second")))
        assertTrue("$first must precede $second", firstCard.visibleBounds.top < secondCard.visibleBounds.top)
    }

    private fun assertSortIconDirection(ascending: Boolean) {
        val label = if (ascending) "切换为时间降序" else "切换为时间升序"
        val bounds = sortButton(label).visibleBounds
        val screenshot = requireNotNull(InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot())
        var topInk = 0
        var bottomInk = 0
        try {
            for (y in bounds.top until bounds.bottom) {
                for (x in bounds.left until bounds.right) {
                    val pixel = screenshot.getPixel(x, y)
                    if (Color.red(pixel) < 100 && Color.green(pixel) < 100 && Color.blue(pixel) < 100) {
                        if (y < bounds.centerY()) topInk++ else bottomInk++
                    }
                }
            }
        } finally {
            screenshot.recycle()
        }
        assertTrue(
            "The bar lengths must increase downwards for ascending order and decrease for descending order",
            if (ascending) topInk < bottomInk else topInk > bottomInk
        )
    }

    private fun sortButton(label: String): UiObject2 {
        val labelNode = requireNotNull(device.findObject(By.desc(label)))
        // Compose may expose the description as a synthetic child of the clickable button.
        return generateSequence(labelNode) { it.parent }.first { it.isClickable }
    }

    private fun repository() = FakeProgrammes().apply {
        catalogue.value = CachedResource(listOf(Programme("1", "News", null, 0)))
        observeDates("1").value = CachedResource(listOf(date))
        observeContents("1", date.id).value = CachedResource(listOf(later, earlier))
    }
}
