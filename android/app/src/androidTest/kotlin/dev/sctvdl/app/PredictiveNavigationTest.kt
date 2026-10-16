package dev.sctvdl.app

import android.os.SystemClock
import androidx.activity.BackEventCompat
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppNavigator
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PredictiveNavigationTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun primaryDestinationsPreviewTheLibraryAndCanCancelOrCommitBack() {
        for (destination in listOf(AppRoute.Downloads, AppRoute.Settings)) {
            val active = mutableSetOf<AppRoute>()
            showRoutes(onEnter = { active.add(it) }, onDispose = { active.remove(it) }).use { scenario ->
                requireNotNull(device.wait(Until.findObject(By.res("tab-${destination::class.simpleName}")), 5_000))
                    .click()
                assertTrue(device.wait(Until.hasObject(By.text("Page ${destination::class.simpleName}")), 5_000))
                awaitActive(scenario, active, setOf(destination))

                startBack(scenario)
                awaitActive(scenario, active, setOf(destination, AppRoute.Catalogue))
                scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }
                awaitActive(scenario, active, setOf(destination))
                assertTrue(device.wait(Until.hasObject(By.text("Page ${destination::class.simpleName}")), 3_000))
                assertTrue(device.wait(Until.gone(By.text("Page Catalogue")), 3_000))

                startBack(scenario)
                scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
                awaitActive(scenario, active, setOf(AppRoute.Catalogue))
                assertTrue(device.wait(Until.hasObject(By.text("Page Catalogue")), 3_000))
                assertTrue(device.wait(Until.gone(By.text("Page ${destination::class.simpleName}")), 3_000))
            }
        }
    }

    @Test fun cancelledDetailBackKeepsItsEntryAndDoesNotCommitDismissal() {
        lateinit var navigator: AppNavigator
        var commits = 0
        val disposed = CountDownLatch(1)
        val active = mutableSetOf<AppRoute>()

        showRoutes(onBackCommitted = {
            commits++
        }, onNavigator = { navigator = it }, onEnter = { active.add(it) }, onDispose = {
            active.remove(it)
            if (it is AppRoute.Archive) disposed.countDown()
        }).use { scenario ->
            assertTrue(device.wait(Until.hasObject(By.text("Page Catalogue")), 5_000))
            scenario.onActivity { navigator.open(AppRoute.Archive("fixture")) }
            assertTrue(device.wait(Until.hasObject(By.text("Page Archive")), 5_000))
            awaitActive(scenario, active, setOf(AppRoute.Archive("fixture")))

            startBack(scenario)
            awaitActive(scenario, active, setOf(AppRoute.Archive("fixture"), AppRoute.Catalogue))
            scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }
            awaitActive(scenario, active, setOf(AppRoute.Archive("fixture")))
            scenario.onActivity { assertEquals(0, commits) }
            assertEquals("Cancellation must preserve the detail entry", 1L, disposed.count)
            assertTrue(device.wait(Until.hasObject(By.text("Page Archive")), 3_000))

            startBack(scenario)
            scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
            assertTrue(disposed.await(3, TimeUnit.SECONDS))
            scenario.onActivity { assertEquals(1, commits) }
            assertTrue(device.wait(Until.hasObject(By.text("Page Catalogue")), 3_000))
        }
    }

    @Test fun primaryBackPreviewDoesNotExposeOrActivateTabActions() {
        val active = mutableSetOf<AppRoute>()
        showRoutes(onEnter = { active.add(it) }, onDispose = { active.remove(it) }).use { scenario ->
            requireNotNull(device.wait(Until.findObject(By.res("tab-Settings")), 5_000)).click()
            awaitActive(scenario, active, setOf(AppRoute.Settings))
            val downloads = requireNotNull(device.wait(Until.findObject(By.res("tab-Downloads")), 3_000)).visibleBounds

            startBack(scenario)
            awaitActive(scenario, active, setOf(AppRoute.Settings, AppRoute.Catalogue))
            assertTrue(
                "A preview must not expose tab actions before commit",
                device.wait(Until.gone(By.res("tab-Downloads")), 1_000)
            )
            device.click(downloads.centerX(), downloads.centerY())
            scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }

            awaitActive(scenario, active, setOf(AppRoute.Settings))
            assertTrue(device.wait(Until.hasObject(By.text("Page Settings")), 3_000))
        }
    }

    @Test fun cancellingPrimaryBackRestoresTabSwitchingFromBothEdges() {
        for (destination in listOf(AppRoute.Downloads, AppRoute.Settings)) {
            for (edge in listOf(BackEventCompat.EDGE_LEFT, BackEventCompat.EDGE_RIGHT)) {
                val active = mutableSetOf<AppRoute>()
                showRoutes(onEnter = { active.add(it) }, onDispose = { active.remove(it) }).use { scenario ->
                    requireNotNull(device.wait(Until.findObject(By.res("tab-${destination::class.simpleName}")), 5_000))
                        .click()
                    awaitActive(scenario, active, setOf(destination))

                    startBack(scenario, edge)
                    awaitActive(scenario, active, setOf(destination, AppRoute.Catalogue))
                    scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }
                    awaitActive(scenario, active, setOf(destination))

                    val alternative = if (destination == AppRoute.Downloads) AppRoute.Settings else AppRoute.Downloads
                    val tab = device.wait(Until.findObject(By.res("tab-${alternative::class.simpleName}")), 3_000)
                    assertTrue("Cancelling back must restore accessible tab actions", tab != null)
                    tab!!.click()
                    awaitActive(scenario, active, setOf(alternative))
                    assertTrue(device.wait(Until.hasObject(By.text("Page ${alternative::class.simpleName}")), 3_000))

                    requireNotNull(device.wait(Until.findObject(By.res("tab-Catalogue")), 3_000)).click()
                    awaitActive(scenario, active, setOf(AppRoute.Catalogue))
                }
            }
        }
    }

    @Test fun primarySwitchFinishesWithinAHalfSecond() {
        lateinit var navigator: AppNavigator
        val disposed = CountDownLatch(1)

        showRoutes(onNavigator = { navigator = it }, onDispose = {
            if (it == AppRoute.Catalogue) disposed.countDown()
        }).use { scenario ->
            assertTrue(device.wait(Until.hasObject(By.text("Page Catalogue")), 5_000))
            device.waitForIdle()
            scenario.onActivity { navigator.open(AppRoute.Downloads) }

            assertTrue(
                "A primary switch must not retain the old page for the default 700 ms",
                disposed.await(
                    500,
                    TimeUnit.MILLISECONDS
                )
            )
            assertTrue(device.wait(Until.hasObject(By.text("Page Downloads")), 3_000))
        }
    }

    private fun startBack(scenario: ActivityScenario<ComponentActivity>, edge: Int = BackEventCompat.EDGE_LEFT) {
        scenario.onActivity {
            it.onBackPressedDispatcher.dispatchOnBackStarted(BackEventCompat(0f, 400f, 0f, edge))
        }
        device.waitForIdle()
        scenario.onActivity {
            it.onBackPressedDispatcher.dispatchOnBackProgressed(
                BackEventCompat(180f, 400f, 0.6f, edge)
            )
        }
        device.waitForIdle()
    }

    private fun awaitActive(
        scenario: ActivityScenario<ComponentActivity>,
        active: Set<AppRoute>,
        expected: Set<AppRoute>
    ) {
        val deadline = SystemClock.uptimeMillis() + 3_000
        var snapshot = emptySet<AppRoute>()
        while (SystemClock.uptimeMillis() < deadline) {
            scenario.onActivity { snapshot = active.toSet() }
            if (snapshot == expected) return
            SystemClock.sleep(16)
        }
        assertEquals("The navigation transition must settle", expected, snapshot)
    }

    private fun showRoutes(
        onBackCommitted: () -> Unit = {},
        onNavigator: (AppNavigator) -> Unit = {},
        onEnter: (AppRoute) -> Unit = {},
        onDispose: (AppRoute) -> Unit = {}
    ): ActivityScenario<ComponentActivity> = ActivityScenario.launch(ComponentActivity::class.java).also { scenario ->
        scenario.onActivity { activity ->
            activity.setContent {
                SctvAppTheme(AppSettings()) {
                    Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                        AppNavigationShell(onBackCommitted = onBackCommitted) { route, navigator, _ ->
                            onNavigator(navigator)
                            DisposableEffect(route) {
                                onEnter(route)
                                onDispose { onDispose(route) }
                            }
                            Text("Page ${route::class.simpleName}")
                        }
                    }
                }
            }
        }
    }
}
