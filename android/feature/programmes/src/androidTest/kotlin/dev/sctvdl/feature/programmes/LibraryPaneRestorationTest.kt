package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
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
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.feature.programmes.catalogue.CatalogueRoute
import dev.sctvdl.feature.programmes.catalogue.CatalogueViewModel
import dev.sctvdl.feature.programmes.presentation.ProgrammeLibraryState
import dev.sctvdl.ui.theme.SctvAppTheme
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryPaneRestorationTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun catalogueScrollSurvivesCompactThenExpandedPane() = checkPaneRestoration(false, false)

    @Test fun favouriteScrollSurvivesArchiveReplacement() = checkPaneRestoration(true, true)

    private fun checkPaneRestoration(favouritesOnly: Boolean, replaceArchive: Boolean) {
        val programmes = (0 until 60).map { Programme("$it", "Fixture $it", null, it) }
        val repository = FakeProgrammes().apply { catalogue.value = CachedResource(programmes) }
        val favourites = FakeFavourites().apply { ids.value = programmes.map { it.id }.toSet() }
        val store = ViewModelStore()
        var expanded by mutableStateOf(true)
        var archive by mutableStateOf("initial")
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val model = CatalogueViewModel(repository, favourites, SavedStateHandle())
                store.put("library", model)
                model.filter(favouritesOnly)
                activity.setContent {
                    val state = model.uiState.collectAsStateWithLifecycle()
                    val library = remember(model) { ProgrammeLibraryState(model, state) }
                    CompositionLocalProvider(LocalDensity provides Density(1f)) {
                        SctvAppTheme(AppSettings()) {
                            Column(
                                Modifier.fillMaxSize().padding(top = 32.dp).semantics { testTagsAsResourceId = true }
                            ) {
                                Text("Archive $archive")
                                BoxWithConstraints(
                                    Modifier.weight(1f).requiredWidth(if (expanded) 1000.dp else 600.dp)
                                ) {
                                    val wide = maxWidth >= 840.dp
                                    key(archive) {
                                        if (wide) {
                                            Box(Modifier.width(340.dp).fillMaxHeight()) {
                                                CatalogueRoute(library, { archive = it }, embedded = true)
                                            }
                                        } else {
                                            Text("Compact archive")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.res("programme-0")), 5_000))
            val grid = requireNotNull(device.findObject(By.res("catalogue-grid")))
            repeat(2) { grid.scroll(Direction.DOWN, 0.75f) }
            device.waitForIdle()
            val before = firstVisibleProgramme()
            assertNotEquals("The fixture must scroll before testing restoration", "programme-0", before)
            if (replaceArchive) {
                requireNotNull(device.findObject(By.res(before))).click()
                scenario.onActivity { assertEquals(before.removePrefix("programme-"), archive) }
            } else {
                scenario.onActivity { expanded = false }
                assertTrue(
                    "Compact windows remove the library pane",
                    device.wait(Until.gone(By.res("catalogue-grid")), 5_000)
                )
                scenario.onActivity { expanded = true }
            }
            requireNotNull(device.wait(Until.findObject(By.res("catalogue-grid")), 5_000))
            device.waitForIdle()
            assertEquals("Recreating the embedded library must retain its visible row", before, firstVisibleProgramme())
            scenario.onActivity { store.clear() }
        }
    }

    private fun firstVisibleProgramme(): String = device.findObjects(By.res(Pattern.compile("programme-.*")))
        .filter { it.visibleBounds.height() > 48 }
        .minBy { it.visibleBounds.top }
        .resourceName
}
