package dev.sctvdl.app

import android.graphics.Bitmap
import android.graphics.Color
import android.os.SystemClock
import androidx.activity.BackEventCompat
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color as ComposeColor
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppNavigator
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.programme.LocalProgrammeCoverTransitionState
import dev.sctvdl.ui.programme.sharedProgrammeCover
import dev.sctvdl.ui.theme.SctvAppTheme
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PredictiveVisualTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val archive = AppRoute.Archive("visual")
    private val playback = AppRoute.Playback("visual", "date", "content")

    @Test fun primaryBackMovesOnlyContentAndKeepsNavigationPixelsAtRest() {
        val fixture = VisualFixture()
        showRoutes(fixture).use { scenario ->
            awaitActive(scenario, fixture, setOf(AppRoute.Catalogue))
            scenario.onActivity { fixture.navigator.open(AppRoute.Settings) }
            awaitActive(scenario, fixture, setOf(AppRoute.Settings))
            val before = pageBounds(scenario, fixture, AppRoute.Settings)
            val navigation = requireNotNull(device.wait(Until.findObject(By.res("tab-Downloads")), 5_000))
                .visibleBounds
            val navigationBefore = screenshot("primary-before")

            startBack(scenario, BackEventCompat.EDGE_LEFT)
            awaitActive(scenario, fixture, setOf(AppRoute.Settings, AppRoute.Catalogue))
            for (progress in listOf(0.2f, 0.5f, 0.8f)) {
                progressBack(scenario, progress, BackEventCompat.EDGE_LEFT)
                val during = pageBounds(scenario, fixture, AppRoute.Settings)
                assertEquals("Primary content must keep its width", before.width, during.width, 2f)
                assertEquals("Primary content must keep its height", before.height, during.height, 2f)
                assertTrue("Primary content must move a short distance", abs(during.left - before.left) in 1f..80f)

                val screenshot = screenshot("primary-$progress")
                try {
                    assertNavigationPixelsAtRest(navigationBefore, screenshot, navigation)
                } finally {
                    screenshot.recycle()
                }
            }
            navigationBefore.recycle()
            scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }
            awaitActive(scenario, fixture, setOf(AppRoute.Settings))
            assertSameBounds(
                "Cancelling must restore the page",
                before,
                pageBounds(scenario, fixture, AppRoute.Settings)
            )
        }
    }

    @Test fun detailBackUsesShortFullSizeMotionFromEitherGestureEdge() {
        for (source in listOf(archive, playback)) {
            for (edge in listOf(BackEventCompat.EDGE_LEFT, BackEventCompat.EDGE_RIGHT)) {
                val fixture = VisualFixture()
                showRoutes(fixture).use { scenario ->
                    awaitActive(scenario, fixture, setOf(AppRoute.Catalogue))
                    scenario.onActivity { fixture.navigator.open(archive) }
                    awaitActive(scenario, fixture, setOf(archive))
                    if (source == playback) {
                        scenario.onActivity { fixture.navigator.open(playback) }
                        awaitActive(scenario, fixture, setOf(playback))
                    }
                    val destination = if (source == playback) archive else AppRoute.Catalogue
                    val before = pageBounds(scenario, fixture, source)
                    var previousDisplacement = 0f

                    startBack(scenario, edge)
                    awaitActive(scenario, fixture, setOf(source, destination))
                    for (progress in listOf(0.2f, 0.5f, 0.8f)) {
                        progressBack(scenario, progress, edge)
                        val during = pageBounds(scenario, fixture, source)
                        assertEquals("A detail page must retain its width", before.width, during.width, 2f)
                        assertEquals("A detail page must retain its top edge", before.top, during.top, 2f)
                        assertEquals("A detail page must retain its bottom edge", before.bottom, during.bottom, 2f)
                        assertEquals("A detail page must retain its height", before.height, during.height, 2f)
                        val displacement = during.left - before.left
                        assertTrue(
                            "A detail preview must stay within a short shared-axis distance",
                            abs(displacement) < 100f
                        )
                        assertTrue(
                            "The page must follow the gesture edge; edge=$edge, displacement=$displacement",
                            if (edge == BackEventCompat.EDGE_LEFT) displacement > 2f else displacement < -2f
                        )
                        assertTrue(
                            "The page must continue translating as the gesture advances",
                            abs(displacement) > previousDisplacement + 2f
                        )
                        previousDisplacement = abs(displacement)
                        screenshot("detail-${source::class.simpleName}-$edge-$progress").recycle()
                    }
                    scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }
                    awaitActive(scenario, fixture, setOf(source))
                    assertSameBounds(
                        "Cancellation must restore the detail",
                        before,
                        pageBounds(scenario, fixture, source)
                    )
                }
            }
        }
    }

    @Test fun matchedCoverSeeksWithBackAndRestoresOnCancelOrCommit() {
        val fixture = VisualFixture(withCover = true)
        showRoutes(fixture).use { scenario ->
            awaitActive(scenario, fixture, setOf(AppRoute.Catalogue))
            val catalogueCover = coverBounds("cover-catalogue")
            scenario.onActivity {
                fixture.selectCover()
                fixture.navigator.open(archive)
            }
            awaitActive(scenario, fixture, setOf(archive))
            val archiveCover = coverBounds("cover-archive")
            var previousDistance = Float.MAX_VALUE

            startBack(scenario, BackEventCompat.EDGE_LEFT)
            awaitActive(scenario, fixture, setOf(archive, AppRoute.Catalogue))
            for (progress in listOf(0.2f, 0.5f, 0.8f)) {
                progressBack(scenario, progress, BackEventCompat.EDGE_LEFT)
                val during = coverBounds("cover-$progress")
                assertTrue(
                    "A matched cover must be one image, without duplicates or stretched bounds",
                    during.width <= maxOf(archiveCover.width, catalogueCover.width) + 6 &&
                        during.height <= maxOf(archiveCover.height, catalogueCover.height) + 6
                )
                val distance = (during.center - catalogueCover.center).getDistance()
                assertTrue(
                    "The cover must move toward its catalogue target with gesture progress",
                    distance < previousDistance
                )
                previousDistance = distance
            }
            scenario.onActivity { it.onBackPressedDispatcher.dispatchOnBackCancelled() }
            awaitActive(scenario, fixture, setOf(archive))
            assertSameBounds("Cancellation must restore the shared cover", archiveCover, coverBounds("cover-cancelled"))

            startBack(scenario, BackEventCompat.EDGE_LEFT)
            awaitActive(scenario, fixture, setOf(archive, AppRoute.Catalogue))
            progressBack(scenario, 0.5f, BackEventCompat.EDGE_LEFT)
            scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
            awaitActive(scenario, fixture, setOf(AppRoute.Catalogue))
            assertSameBounds(
                "Commit must restore the matched catalogue cover",
                catalogueCover,
                coverBounds("cover-committed")
            )
        }
    }

    private fun showRoutes(fixture: VisualFixture): ActivityScenario<ComponentActivity> =
        ActivityScenario.launch(ComponentActivity::class.java).also { scenario ->
            scenario.onActivity { activity ->
                activity.enableEdgeToEdge()
                activity.setContent {
                    val density = LocalDensity.current
                    val compactDensity = maxOf(density.density, activity.resources.displayMetrics.widthPixels / 400f)
                    CompositionLocalProvider(LocalDensity provides Density(compactDensity, 1f)) {
                        SctvAppTheme(AppSettings(theme = ThemeMode.Light)) {
                            Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                                AppNavigationShell { route, navigator, _ ->
                                    fixture.navigator = navigator
                                    val coverTransition = LocalProgrammeCoverTransitionState.current
                                    fixture.selectCover = { coverTransition?.select(fixture.programme) }
                                    DisposableEffect(route) {
                                        fixture.active.add(route)
                                        onDispose { fixture.active.remove(route) }
                                    }
                                    val pageColour = if (route == AppRoute.Catalogue) {
                                        ComposeColor(0xFF00AA66)
                                    } else {
                                        ComposeColor(0xFF0055BB)
                                    }
                                    Box(
                                        Modifier.fillMaxSize().onGloballyPositioned { fixture.pages[route] = it }
                                            .background(pageColour)
                                    ) {
                                        Text(
                                            "Visual ${route::class.simpleName}",
                                            Modifier.padding(8.dp),
                                            color = ComposeColor.White
                                        )
                                        if (fixture.withCover && (route == AppRoute.Catalogue || route == archive)) {
                                            val catalogue = route == AppRoute.Catalogue
                                            Box(
                                                Modifier.offset(
                                                    x = if (catalogue) 24.dp else 160.dp,
                                                    y = if (catalogue) 80.dp else 260.dp
                                                ).size(
                                                    width = if (catalogue) 120.dp else 144.dp,
                                                    height = if (catalogue) 72.dp else 90.dp
                                                )
                                            ) {
                                                Box(
                                                    Modifier.fillMaxSize()
                                                        .sharedProgrammeCover(fixture.programme, RectangleShape)
                                                        .background(ComposeColor(0xFFFF00DD))
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

    private fun assertNavigationPixelsAtRest(before: Bitmap, during: Bitmap, bounds: android.graphics.Rect) {
        var changed = 0
        var samples = 0
        for (y in bounds.top until bounds.bottom step 2) {
            for (x in bounds.left until bounds.right step 2) {
                val original = before.getPixel(x, y)
                val current = during.getPixel(x, y)
                val difference = abs(Color.red(original) - Color.red(current)) +
                    abs(Color.green(original) - Color.green(current)) + abs(Color.blue(original) - Color.blue(current))
                if (difference > 30) changed++
                samples++
            }
        }
        assertTrue(
            "Unselected navigation must not move or fade with page content; changed=$changed/$samples",
            changed < samples / 100
        )
    }

    private fun coverBounds(name: String): Rect {
        val bitmap = screenshot(name)
        var left = bitmap.width
        var top = bitmap.height
        var right = 0
        var bottom = 0
        try {
            for (y in 0 until bitmap.height) {
                for (x in 0 until bitmap.width) {
                    val pixel = bitmap.getPixel(x, y)
                    if (Color.red(pixel) > 150 && Color.green(pixel) < 80 && Color.blue(pixel) > 120) {
                        left = minOf(left, x)
                        top = minOf(top, y)
                        right = maxOf(right, x + 1)
                        bottom = maxOf(bottom, y + 1)
                    }
                }
            }
        } finally {
            bitmap.recycle()
        }
        assertTrue("A real shared cover must be visible in $name", right > left && bottom > top)
        return Rect(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
    }

    private fun pageBounds(
        scenario: ActivityScenario<ComponentActivity>,
        fixture: VisualFixture,
        route: AppRoute
    ): Rect {
        var bounds: Rect? = null
        scenario.onActivity {
            bounds = fixture.pages[route]?.takeIf { it.isAttached }?.boundsInWindow(clipBounds = false)
        }
        return requireNotNull(bounds) { "The $route page must have attached layout coordinates" }
    }

    private fun assertSameBounds(message: String, expected: Rect, actual: Rect) {
        assertEquals("$message: width", expected.width, actual.width, 2f)
        assertEquals("$message: height", expected.height, actual.height, 2f)
        assertEquals("$message: left", expected.left, actual.left, 2f)
        assertEquals("$message: top", expected.top, actual.top, 2f)
    }

    private fun startBack(scenario: ActivityScenario<ComponentActivity>, edge: Int) {
        scenario.onActivity {
            it.onBackPressedDispatcher.dispatchOnBackStarted(BackEventCompat(0f, 400f, 0f, edge))
        }
        awaitFrame(scenario)
    }

    private fun progressBack(scenario: ActivityScenario<ComponentActivity>, progress: Float, edge: Int) {
        scenario.onActivity {
            it.onBackPressedDispatcher.dispatchOnBackProgressed(BackEventCompat(180f, 400f, progress, edge))
        }
        awaitFrame(scenario)
        device.waitForIdle()
    }

    private fun awaitFrame(scenario: ActivityScenario<ComponentActivity>) {
        val drawn = CountDownLatch(1)
        scenario.onActivity { activity ->
            activity.window.decorView.postOnAnimation {
                activity.window.decorView.postOnAnimation { drawn.countDown() }
            }
            activity.window.decorView.invalidate()
        }
        assertTrue("The synthetic back event must reach a rendered frame", drawn.await(3, TimeUnit.SECONDS))
        instrumentation.waitForIdleSync()
    }

    private fun awaitActive(
        scenario: ActivityScenario<ComponentActivity>,
        fixture: VisualFixture,
        expected: Set<AppRoute>
    ) {
        val deadline = SystemClock.uptimeMillis() + 5_000
        var active = emptySet<AppRoute>()
        while (SystemClock.uptimeMillis() < deadline) {
            scenario.onActivity { active = fixture.active.toSet() }
            if (active == expected) {
                awaitFrame(scenario)
                return
            }
            SystemClock.sleep(16)
        }
        assertEquals("The expected pages must be composed before measuring geometry", expected, active)
    }

    private fun screenshot(name: String): Bitmap {
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        val directory = File(instrumentation.targetContext.getExternalFilesDir(null), "predictive-visual")
        directory.mkdirs()
        File(directory, "$name.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return image
    }

    private class VisualFixture(val withCover: Boolean = false) {
        val programme = Programme("visual", "Visual cover", "fixture-cover", 0)
        val active = mutableSetOf<AppRoute>()
        val pages = mutableMapOf<AppRoute, LayoutCoordinates>()
        lateinit var navigator: AppNavigator
        var selectCover: () -> Unit = {}
    }
}
