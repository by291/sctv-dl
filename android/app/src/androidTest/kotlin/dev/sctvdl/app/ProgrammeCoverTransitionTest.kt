package dev.sctvdl.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.features.archive.ArchiveScreen
import dev.sctvdl.app.features.archive.ArchiveUiState
import dev.sctvdl.app.features.catalogue.CatalogueScreen
import dev.sctvdl.app.features.catalogue.CatalogueUiState
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import java.io.File
import kotlin.math.abs
import kotlin.math.atan
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgrammeCoverTransitionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val coverColour = Color.rgb(244, 0, 221)

    @Test fun gridCoverTravelsToTheHeaderAndBackWhenTheSameProgrammeIsFeatured() {
        withCatalogue { _ ->
            val card = requireNotNull(device.wait(Until.findObject(By.res("programme-fixture")), 5_000))
            val source = awaitCover(card.visibleBounds).bounds
            device.click(card.visibleBounds.centerX(), card.visibleBounds.centerY())
            val forwardFrames = captureTransition()
            assertTrue(device.wait(Until.hasObject(By.text("栏目详情")), 5_000))
            val destination = awaitCover().bounds
            assertTravelsBetween(forwardFrames.map { it.bounds }, source, destination)

            val back = requireNotNull(device.findObject(By.desc("返回")))
            device.click(back.visibleBounds.centerX(), back.visibleBounds.centerY())
            val returnFrames = captureTransition()
            assertTrue(device.wait(Until.hasObject(By.res("programme-fixture")), 5_000))
            assertTravelsBetween(returnFrames.map { it.bounds }, destination, source)
        }
    }

    @Test fun spotlightCoverTravelsFromTheFeaturedArtworkRatherThanTheDuplicateGridCard() {
        withCatalogue { _ ->
            val spotlight = requireNotNull(device.wait(Until.findObject(By.res("programme-spotlight")), 5_000))
            val source = awaitCover(spotlight.visibleBounds)
            assertTrue("The spotlight starts tilted: $source", source.rotation in -6.0..-4.0)
            val open = requireNotNull(device.findObject(By.desc("查看栏目转场测试栏目")))
            device.click(open.visibleBounds.centerX(), open.visibleBounds.centerY())
            val frames = captureTransition()
            assertTrue(device.wait(Until.hasObject(By.text("栏目详情")), 5_000))
            val destination = awaitCover()
            assertTravelsBetween(frames.map { it.bounds }, source.bounds, destination.bounds)
            assertRotatesWhileTravelling(frames, source, destination)

            val back = requireNotNull(device.findObject(By.desc("返回")))
            device.click(back.visibleBounds.centerX(), back.visibleBounds.centerY())
            val returnFrames = captureTransition()
            assertTrue(device.wait(Until.hasObject(By.res("programme-fixture")), 5_000))
            assertRotatesWhileTravelling(returnFrames, destination, source)

            val card = requireNotNull(device.findObject(By.res("programme-fixture")))
            device.click(card.visibleBounds.centerX(), card.visibleBounds.centerY())
            val gridFrames = captureTransition().filter {
                it.bounds.height() <= maxOf(source.bounds.height(), destination.bounds.height()) + 12
            }
            assertTrue("The next grid open must have measurable frames", gridFrames.isNotEmpty())
            assertTrue("The next grid open must remain upright: $gridFrames", gridFrames.all { abs(it.rotation) < 0.7 })
        }
    }

    private fun withCatalogue(block: (ActivityScenario<ComponentActivity>) -> Unit) {
        val cover = File(instrumentation.targetContext.cacheDir, "shared-cover-fixture.png")
        val bitmap = Bitmap.createBitmap(320, 180, Bitmap.Config.ARGB_8888).apply { eraseColor(coverColour) }
        // The internal stripe remains measurable even when the shared layer clips the outer image edges.
        Canvas(bitmap).drawRect(0f, 84f, 320f, 96f, Paint().apply { color = Color.rgb(0, 244, 20) })
        try {
            cover.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val programme = Programme("fixture", "转场测试栏目", cover.toURI().toString(), 0)
            ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    activity.setContent {
                        SctvTheme(AppSettings()) {
                            Box(Modifier.semantics { testTagsAsResourceId = true }) {
                                AppNavigationShell { route, navigator ->
                                    when (route) {
                                        AppRoute.Catalogue -> CatalogueScreen(
                                            CatalogueUiState(
                                                resource = CachedResource(listOf(programme)),
                                                featuredId = programme.id
                                            ),
                                            false,
                                            {},
                                            {},
                                            {},
                                            {},
                                            { navigator.open(AppRoute.Archive(it)) },
                                            {}
                                        )
                                        is AppRoute.Archive -> ArchiveScreen(
                                            ArchiveUiState(
                                                programmeId = programme.id,
                                                programme = programme,
                                                dates = CachedResource(emptyList())
                                            ),
                                            false, navigator.back, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
                                        )
                                        else -> Unit
                                    }
                                }
                            }
                        }
                    }
                }
                block(scenario)
            }
        } finally {
            bitmap.recycle()
            cover.delete()
        }
    }

    private data class CoverFrame(val bounds: Rect, val rotation: Double)

    private fun awaitCover(region: Rect? = null): CoverFrame {
        var result: CoverFrame? = null
        val deadline = System.currentTimeMillis() + 5_000
        while (result == null && System.currentTimeMillis() < deadline) {
            val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            result = findCover(screenshot, region)
            screenshot.recycle()
            if (result == null) Thread.sleep(30)
        }
        return requireNotNull(result) { "The real cover must be decoded before navigation" }
    }

    private fun captureTransition(): List<CoverFrame> {
        val frames = mutableListOf<CoverFrame>()
        val deadline = System.currentTimeMillis() + 900
        while (System.currentTimeMillis() < deadline) {
            val screenshot = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
            findCover(screenshot)?.let(frames::add)
            screenshot.recycle()
            Thread.sleep(20)
        }
        return frames
    }

    private fun findCover(bitmap: Bitmap, region: Rect? = null): CoverFrame? {
        val bounds = region ?: Rect(0, 0, bitmap.width, bitmap.height)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        var left = bitmap.width
        var top = bitmap.height
        var right = 0
        var bottom = 0
        for (y in bounds.top.coerceAtLeast(0) until bounds.bottom.coerceAtMost(bitmap.height) step 3) {
            for (x in bounds.left.coerceAtLeast(0) until bounds.right.coerceAtMost(bitmap.width) step 3) {
                val pixel = pixels[y * bitmap.width + x]
                if (isCoverPixel(pixel)) {
                    left = minOf(left, x)
                    top = minOf(top, y)
                    right = maxOf(right, x)
                    bottom = maxOf(bottom, y)
                }
            }
        }
        if (right <= left || bottom <= top) return null
        val rectangle = Rect(left, top, right, bottom)
        val firstX = left + rectangle.width() / 4
        val lastX = right - rectangle.width() / 4
        fun stripeAt(x: Int) = (top..bottom).firstOrNull {
            val pixel = pixels[it * bitmap.width + x]
            Color.red(pixel) < 12 && abs(Color.green(pixel) - 244) < 12 && abs(Color.blue(pixel) - 20) < 12
        }
        val firstY = stripeAt(firstX) ?: return null
        val lastY = stripeAt(lastX) ?: return null
        val slope = (lastY - firstY).toDouble() / (lastX - firstX)
        return CoverFrame(rectangle, Math.toDegrees(atan(slope)))
    }

    private fun isCoverPixel(pixel: Int) = abs(Color.red(pixel) - 244) < 12 && Color.green(pixel) < 12 &&
        abs(Color.blue(pixel) - 221) < 12

    private fun assertRotatesWhileTravelling(frames: List<CoverFrame>, source: CoverFrame, destination: CoverFrame) {
        val displacement = destination.bounds.exactCenterX() - source.bounds.exactCenterX()
        val movingFrames = frames.filter {
            it.bounds.height() <= maxOf(source.bounds.height(), destination.bounds.height()) + 12 &&
                (it.bounds.exactCenterX() - source.bounds.exactCenterX()) / displacement in 0.2f..0.8f
        }
        assertTrue(
            "Rotation must have intermediate frames during displacement: $movingFrames",
            movingFrames.isNotEmpty()
        )
        movingFrames.forEach {
            val progress = (it.bounds.exactCenterX() - source.bounds.exactCenterX()) / displacement
            val expected = source.rotation + (destination.rotation - source.rotation) * progress
            assertTrue(
                "Rotation must follow the same progress as displacement; expected=$expected, frame=$it",
                abs(it.rotation - expected) < 0.9
            )
        }
    }

    private fun assertTravelsBetween(frames: List<Rect>, source: Rect, destination: Rect) {
        val upper = minOf(source.top, destination.top) + 12
        val lower = maxOf(source.top, destination.top) - 12
        val horizontalMovement = abs(source.left - destination.left) > 24
        val left = minOf(source.left, destination.left) + 12
        val right = maxOf(source.left, destination.left) - 12
        assertTrue(
            "The decoded cover must move between its endpoints, rather than fade at fixed positions: " +
                "$source -> $destination; frames=$frames",
            frames.any {
                it.top in upper..lower && (!horizontalMovement || it.left in left..right) &&
                    it.height() <= maxOf(source.height(), destination.height()) + 12
            }
        )
    }
}
