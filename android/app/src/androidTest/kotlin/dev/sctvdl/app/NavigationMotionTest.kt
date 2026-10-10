package dev.sctvdl.app

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppNavigator
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NavigationMotionTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun catalogueDoesNotExpandIntoTheNavigationBarDuringArchiveEntry() {
        val heights = mutableListOf<Int>()
        lateinit var navigator: AppNavigator

        showRoutes(ThemeMode.Light, 1f) { route, navigation, _ ->
            navigator = navigation
            Box(
                Modifier.fillMaxSize().onSizeChanged {
                    if (route == AppRoute.Catalogue) heights.add(it.height)
                }
            ) {
                Text("Page ${route::class.simpleName}")
            }
        }.use { scenario ->
            requireNotNull(device.wait(Until.findObject(By.res("tab-Catalogue")), 5_000))
            device.waitForIdle()
            var initialHeight = 0
            scenario.onActivity {
                initialHeight = heights.last()
                assertTrue(initialHeight > 0)
                heights.clear()
                navigator.open(AppRoute.Archive("one"))
            }

            requireNotNull(device.wait(Until.findObject(By.text("Page Archive")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                assertTrue(
                    "The outgoing library must keep its viewport throughout the transition: $heights",
                    heights.all { it == initialHeight }
                )
            }
            assertNull(device.findObject(By.res("tab-Catalogue")))
        }
    }

    @Test fun archiveKeepsItsGestureInsetWhileReturningToBottomNavigation() {
        val archivePadding = mutableListOf<Dp>()
        lateinit var navigator: AppNavigator

        showRoutes(ThemeMode.Dark, 2f) { route, navigation, bottomPadding ->
            navigator = navigation
            if (route is AppRoute.Archive && archivePadding.lastOrNull() != bottomPadding) {
                archivePadding.add(bottomPadding)
            }
            Text("Page ${route::class.simpleName}")
        }.use { scenario ->
            requireNotNull(device.wait(Until.findObject(By.res("tab-Catalogue")), 5_000))
            scenario.onActivity { navigator.open(AppRoute.Archive("one")) }
            requireNotNull(device.wait(Until.findObject(By.text("Page Archive")), 5_000))
            device.waitForIdle()
            var initialPadding = 0.dp
            scenario.onActivity {
                initialPadding = archivePadding.last()
                assertTrue(initialPadding > 0.dp)
                archivePadding.clear()
                navigator.back()
            }

            requireNotNull(device.wait(Until.findObject(By.res("tab-Catalogue")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                for (padding in archivePadding) {
                    assertEquals("Returning navigation must not resize the outgoing archive", initialPadding, padding)
                }
            }
        }
    }

    private fun showRoutes(
        theme: ThemeMode,
        fontScale: Float,
        content: @Composable (AppRoute, AppNavigator, Dp) -> Unit
    ): ActivityScenario<ComponentActivity> = ActivityScenario.launch(ComponentActivity::class.java).also { scenario ->
        scenario.onActivity { activity ->
            activity.enableEdgeToEdge()
            activity.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    SctvAppTheme(AppSettings(theme = theme)) {
                        Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                            AppNavigationShell(content = content)
                        }
                    }
                }
            }
        }
    }
}
