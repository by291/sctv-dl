package dev.sctvdl.feature.programmes

import android.graphics.Rect
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material3.Button
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.feature.programmes.catalogue.CatalogueRoute
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueViewModel
import dev.sctvdl.feature.programmes.presentation.ProgrammeLibraryState
import dev.sctvdl.ui.theme.SctvAppTheme
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryFavouriteStabilityTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun serviceOrderedCardsKeepTheirPositionsWhenFavouritesChange() =
        checkFavouriteStability(byName = false, largeText = false)

    @Test fun nameOrderedDarkLargeTextCardsKeepTheirPositionsWhenFavouritesChange() =
        checkFavouriteStability(byName = true, largeText = true)

    @Test fun routeReentryResumeAndContentUpdateKeepStartupFavouritePriority() {
        val programmes = (0 until 4).map { Programme("$it", "Fixture $it", null, it) }
        val repository = FakeProgrammes().apply { catalogue.value = CachedResource(programmes) }
        val favourites = FakeFavourites().apply { ids.value = setOf("3") }
        val store = ViewModelStore()
        var inLibrary by mutableStateOf(true)
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    val model = CatalogueViewModel(repository, favourites, SavedStateHandle())
                    store.put("library", model)
                    activity.setContent {
                        val state = model.uiState.collectAsStateWithLifecycle()
                        val library = remember(model) { ProgrammeLibraryState(model, state) }
                        CompositionLocalProvider(LocalDensity provides Density(1f)) {
                            Box(
                                Modifier.requiredSize(360.dp, 800.dp).semantics { testTagsAsResourceId = true }
                            ) {
                                SctvAppTheme(AppSettings(theme = ThemeMode.Light)) {
                                    Surface {
                                        if (inLibrary) {
                                            CatalogueRoute(library, { inLibrary = false }, embedded = true)
                                        } else {
                                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                                Button(onClick = { inLibrary = true }) { Text("Return to library") }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                assertNotNull(device.wait(Until.findObject(By.text("4 个栏目")), 5_000))
                device.waitForIdle()
                assertEquals("programme-3", visibleCardBounds().keys.first())

                requireNotNull(device.findObject(By.desc("取消收藏Fixture 3"))).click()
                assertNotNull(device.wait(Until.findObject(By.desc("收藏Fixture 3")), 5_000))
                requireNotNull(device.findObject(By.desc("收藏Fixture 2"))).click()
                assertNotNull(device.wait(Until.findObject(By.desc("取消收藏Fixture 2")), 5_000))
                assertEquals("programme-3", visibleCardBounds().keys.first())

                requireNotNull(device.findObject(By.res("programme-3"))).click()
                scenario.onActivity { assertTrue("Opening a programme must leave the library", !inLibrary) }
                requireNotNull(device.wait(Until.findObject(By.text("Return to library")), 5_000)).click()
                assertNotNull(device.wait(Until.findObject(By.text("4 个栏目")), 5_000))
                device.waitForIdle()
                assertEquals("programme-3", visibleCardBounds().keys.first())

                scenario.moveToState(Lifecycle.State.CREATED)
                favourites.ids.value = favourites.ids.value + "0"
                scenario.moveToState(Lifecycle.State.RESUMED)
                assertNotNull(device.wait(Until.findObject(By.desc("取消收藏Fixture 0")), 5_000))
                assertEquals("programme-3", visibleCardBounds().keys.first())

                requireNotNull(device.findObject(By.desc("收藏Fixture 1"))).click()
                assertNotNull(device.wait(Until.findObject(By.desc("取消收藏Fixture 1")), 5_000))
                scenario.onActivity {
                    repository.catalogue.value = CachedResource(programmes.map { it.copy(name = "Updated ${it.name}") })
                }
                val update = requireNotNull(device.wait(Until.findObject(By.desc("有新内容，点击更新")), 5_000))
                assertEquals("programme-3", visibleCardBounds().keys.first())
                update.click()
                assertNotNull(device.wait(Until.findObject(By.text("Updated Fixture 1")), 5_000))
                device.waitForIdle()
                assertEquals("programme-3", visibleCardBounds().keys.first())
            } finally {
                scenario.onActivity { store.clear() }
            }
        }
    }

    private fun checkFavouriteStability(byName: Boolean, largeText: Boolean) {
        val programmes = (0 until 60).map {
            Programme("$it", "Fixture ${it.toString().padStart(2, '0')}", null, 59 - it)
        }
        val repository = FakeProgrammes().apply { catalogue.value = CachedResource(programmes) }
        val store = ViewModelStore()
        lateinit var scroll: LazyGridState
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    val model = CatalogueViewModel(
                        repository,
                        FakeFavourites(),
                        SavedStateHandle(mapOf("byName" to byName, "featuredId" to "0"))
                    )
                    store.put("library", model)
                    activity.setContent {
                        val state by model.uiState.collectAsStateWithLifecycle()
                        scroll = rememberLazyGridState()
                        CompositionLocalProvider(LocalDensity provides Density(1f, if (largeText) 2f else 1f)) {
                            Box(
                                Modifier.requiredSize(if (largeText) 320.dp else 360.dp, 800.dp)
                                    .semantics { testTagsAsResourceId = true }
                            ) {
                                SctvAppTheme(AppSettings(theme = if (largeText) ThemeMode.Dark else ThemeMode.Light)) {
                                    Surface {
                                        CatalogueScreen(
                                            state, state.favouritesOnly, model::query, model::sort, model::refresh,
                                            model::toggleFavourite, {}, model::filter, model::exploreAnother,
                                            catalogueScroll = scroll
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                assertNotNull(device.wait(Until.findObject(By.text("60 个栏目")), 5_000))
                val grid = requireNotNull(device.findObject(By.res("catalogue-grid")))
                repeat(2) { grid.scroll(Direction.DOWN, 0.7f) }
                device.waitForIdle()
                val before = visibleCardBounds()
                assertTrue("The fixture must have fully visible cards after scrolling", before.isNotEmpty())
                var position = 0 to 0
                scenario.onActivity { position = scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset }
                assertTrue("The fixture must scroll before toggling a favourite", position.first > 0)
                val id = before.keys.last().removePrefix("programme-")
                val name = programmes.first { it.id == id }.name

                requireNotNull(device.findObject(By.desc("收藏$name"))).click()
                assertNotNull(device.wait(Until.findObject(By.desc("取消收藏$name")), 5_000))
                assertEquals(before, visibleCardBounds())
                scenario.onActivity {
                    assertEquals(position, scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset)
                }

                requireNotNull(device.findObject(By.res("filter-favourites"))).click()
                assertNotNull(device.wait(Until.findObject(By.text("1 个栏目")), 5_000))
                assertNotNull(device.findObject(By.res("programme-$id")))
                requireNotNull(device.findObject(By.res("filter-all"))).click()
                assertNotNull(device.wait(Until.findObject(By.desc("取消收藏$name")), 5_000))
                assertEquals(before, visibleCardBounds())

                requireNotNull(device.findObject(By.desc("取消收藏$name"))).click()
                assertNotNull(device.wait(Until.findObject(By.desc("收藏$name")), 5_000))
                assertEquals(before, visibleCardBounds())
                scenario.onActivity {
                    assertEquals(position, scroll.firstVisibleItemIndex to scroll.firstVisibleItemScrollOffset)
                }
            } finally {
                scenario.onActivity { store.clear() }
            }
        }
    }

    private fun visibleCardBounds(): Map<String, Rect> {
        val gridBounds = requireNotNull(device.findObject(By.res("catalogue-grid"))).visibleBounds
        return device.findObjects(By.res(Pattern.compile("programme-\\d+")))
            .filter { gridBounds.contains(it.visibleBounds) }
            .sortedWith(compareBy({ it.visibleBounds.top }, { it.visibleBounds.left }))
            .associate { it.resourceName to Rect(it.visibleBounds) }
    }
}
