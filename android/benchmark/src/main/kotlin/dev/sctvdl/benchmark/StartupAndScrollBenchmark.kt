package dev.sctvdl.benchmark

import android.content.Intent
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import java.util.regex.Pattern
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

private const val APP_PACKAGE = "dev.sctvdl.app"
private const val FIXTURE_ACTIVITY =
    "dev.sctvdl.feature.programmes.catalogue.CatalogueBenchmarkActivity"
private const val FIXTURE_TIMEOUT_MS = 20_000L
private const val GESTURE_MARGIN_DIVISOR = 5
private val programmeCard = By.res(Pattern.compile("programme-[0-9]+"))
private val catalogueGrid = By.res("catalogue-grid")

class StartupAndScrollBenchmark {
    @get:Rule val benchmark = MacrobenchmarkRule()

    @Test
    fun coldStartup() = benchmark.measureRepeated(
        packageName = APP_PACKAGE,
        metrics = listOf(StartupTimingMetric()),
        iterations = 5,
        startupMode = StartupMode.COLD,
        compilationMode = CompilationMode.Partial(),
        setupBlock = { pressHome() }
    ) { startActivityAndWait() }

    @Test
    fun catalogueScroll() = benchmark.measureRepeated(
        packageName = APP_PACKAGE,
        metrics = listOf(FrameTimingMetric()),
        iterations = 5,
        compilationMode = CompilationMode.Partial(),
        setupBlock = {
            pressHome()
            val fixture = Intent(Intent.ACTION_MAIN)
                .setClassName(APP_PACKAGE, FIXTURE_ACTIVITY)
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
            startActivityAndWait(fixture)
            requireNotNull(device.wait(Until.findObject(By.res("programme-1")), FIXTURE_TIMEOUT_MS))
        }
    ) {
        val grid = requireNotNull(device.findObject(catalogueGrid))
        val initialProgramme = firstVisibleProgramme(grid)
        assertEquals(1, initialProgramme)
        grid.setGestureMargin(grid.visibleBounds.width() / GESTURE_MARGIN_DIVISOR)

        grid.fling(Direction.DOWN)
        device.waitForIdle()
        val programmeAfterDown = firstVisibleProgramme(grid)
        assertTrue("Fling down must advance the viewport", programmeAfterDown > initialProgramme)

        grid.fling(Direction.UP)
        device.waitForIdle()
        val programmeAfterUp = firstVisibleProgramme(grid)
        assertTrue("Fling up must move toward the start", programmeAfterUp < programmeAfterDown)
    }

    private fun firstVisibleProgramme(grid: UiObject2): Int {
        val cards = grid.findObjects(programmeCard).filter { !it.visibleBounds.isEmpty }
        check(cards.isNotEmpty()) { "Catalogue fixture cards must be visible" }
        return cards.minOf { card ->
            val tag = requireNotNull(card.resourceName)
            tag.substringAfterLast('-').toInt()
        }
    }
}
