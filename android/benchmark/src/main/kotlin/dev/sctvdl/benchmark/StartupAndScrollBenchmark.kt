package dev.sctvdl.benchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test

class StartupAndScrollBenchmark {
    @get:Rule val benchmark = MacrobenchmarkRule()

    @Test
    fun coldStartup() = benchmark.measureRepeated(
        packageName = "dev.sctvdl.app",
        metrics = listOf(StartupTimingMetric()),
        iterations = 5,
        startupMode = StartupMode.COLD,
        compilationMode = CompilationMode.Partial(),
        setupBlock = { pressHome() }
    ) { startActivityAndWait() }

    @Test
    fun catalogueScroll() = benchmark.measureRepeated(
        packageName = "dev.sctvdl.app",
        metrics = listOf(FrameTimingMetric()),
        iterations = 5,
        compilationMode = CompilationMode.Partial(),
        setupBlock = {
            pressHome()
            startActivityAndWait()
            assertNotNull(device.wait(Until.findObject(By.res("catalogue-grid")), 20_000))
        }
    ) {
        val grid = requireNotNull(device.findObject(By.res("catalogue-grid")))
        grid.setGestureMargin(device.displayWidth / 5)
        grid.fling(Direction.DOWN)
        device.waitForIdle()
        grid.fling(Direction.UP)
        device.waitForIdle()
    }
}
