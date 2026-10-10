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
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LibraryLoadingTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun uncachedLoadingPreservesExplorationAndGridUntilAnErrorOrEmptyResponse() {
        var state by mutableStateOf(CatalogueUiState(resource = CachedResource(isRefreshing = true)))
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            CatalogueScreen(state, false, {}, {}, {}, {}, {}, {})
                        }
                    }
                }
            }
            val exploration = device.wait(Until.findObject(By.res("spotlight-placeholder")), 5_000)
            assertNotNull("The initial header must reserve space for exploration", exploration)
            val card = requireNotNull(device.wait(Until.findObject(By.res("programme-placeholder-0")), 5_000))
            assertTrue(card.visibleBounds.top >= exploration!!.visibleBounds.bottom)
            assertTrue("Skeleton cards must not expose fake playable programmes", !card.isClickable)
            scenario.onActivity {
                state = state.copy(resource = CachedResource(error = AppError(ErrorKind.Network, "Fixture error")))
            }
            assertTrue(device.wait(Until.gone(By.res("spotlight-placeholder")), 5_000))
            assertNotNull(device.wait(Until.findObject(By.text("重新连接")), 5_000))
            scenario.onActivity { state = state.copy(resource = CachedResource(emptyList())) }
            assertNotNull(device.wait(Until.findObject(By.text("暂无栏目")), 5_000))
            assertNull(device.findObject(By.res("programme-placeholder-0")))
        }
    }

    @Test fun cachedRefreshKeepsRealProgrammesInsteadOfSkeletons() {
        val programme = Programme("one", "Alpha", null, 0)
        var state by mutableStateOf(
            CatalogueUiState(resource = CachedResource(listOf(programme)), featuredId = "one")
        )
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            CatalogueScreen(
                                state,
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
            assertNotNull(device.wait(Until.findObject(By.res("programme-one")), 5_000))
            scenario.onActivity { state = state.copy(resource = state.resource.copy(isRefreshing = true)) }
            device.waitForIdle()
            assertNull(device.findObject(By.clazz("android.widget.ProgressBar")))
            assertNotNull(device.findObject(By.res("programme-one")))
            assertNull(device.findObject(By.res("programme-placeholder-0")))
            scenario.onActivity { state = state.copy(resource = state.resource.copy(isRefreshing = false)) }
            assertTrue(device.wait(Until.gone(By.clazz("android.widget.ProgressBar")), 5_000))
        }
    }
}
