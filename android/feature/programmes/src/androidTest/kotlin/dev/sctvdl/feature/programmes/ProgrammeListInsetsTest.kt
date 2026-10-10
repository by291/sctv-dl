package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
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
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.programmes.archive.ArchiveScreen
import dev.sctvdl.feature.programmes.archive.ArchiveUiState
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgrammeListInsetsTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val bottomPadding = 120.dp
    private val programme = Programme("one", "Programme", null, 0)
    private val date = BroadcastDate("date", LocalDate.of(2026, 10, 10))
    private val clips = (0 until 30).map { ProgrammeContent("$it", "Clip $it", standardUrl = "clip.mp4") }

    @Test fun catalogueLastCardClearsSystemInsetsInBothThemesAndLargeText() {
        for (theme in listOf(ThemeMode.Light, ThemeMode.Dark)) {
            showScreen(theme, if (theme == ThemeMode.Dark) 2f else 1f) {
                CatalogueScreen(
                    CatalogueUiState(
                        resource = CachedResource(
                            (0 until 20).map {
                                Programme("$it", "Programme $it", null, it)
                            }
                        )
                    ),
                    false, {}, {}, {}, {}, {}, {},
                    bottomContentPadding = bottomPadding
                )
            }.use {
                assertListEndIsSafe("catalogue-grid", "programme-19")
            }
        }
    }

    @Test fun archiveLastVideoSettlesAboveGestureNavigationInBothThemesAndLargeText() {
        for (theme in listOf(ThemeMode.Light, ThemeMode.Dark)) {
            showScreen(theme, if (theme == ThemeMode.Dark) 2f else 1f) {
                ArchiveScreen(
                    ArchiveUiState(
                        programmeId = "one",
                        programme = programme,
                        dates = CachedResource(listOf(date)),
                        date = date,
                        contents = CachedResource(clips)
                    ),
                    false, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {},
                    bottomContentPadding = bottomPadding
                )
            }.use {
                assertListEndIsSafe("archive-list", "content-29")
            }
        }
    }

    @Test fun fixedBatchDownloadRemainsAboveGestureNavigation() {
        showScreen(ThemeMode.Dark, 2f) {
            ArchiveScreen(
                ArchiveUiState(
                    programmeId = "one",
                    programme = programme,
                    dates = CachedResource(listOf(date)),
                    date = date,
                    contents = CachedResource(clips),
                    selectionMode = true,
                    selectedIds = setOf("0")
                ),
                false, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {},
                bottomContentPadding = bottomPadding
            )
        }.use {
            val download = requireNotNull(device.wait(Until.findObject(By.text("下载所选（1）")), 5_000))
            assertTrue(
                "The batch action must remain usable above navigation",
                download.visibleBounds.bottom <= safeBottom
            )
        }
    }

    private var windowBottom = 0f
    private var safeBottom = 0f

    private fun showScreen(
        theme: ThemeMode,
        fontScale: Float,
        content: @Composable () -> Unit
    ): ActivityScenario<ComponentActivity> {
        val scenario = ActivityScenario.launch(ComponentActivity::class.java)
        scenario.onActivity { activity ->
            activity.enableEdgeToEdge()
            activity.setContent {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    SctvAppTheme(AppSettings(theme = theme)) {
                        val paddingPx = with(LocalDensity.current) { bottomPadding.toPx() }
                        Box(
                            Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }.onGloballyPositioned {
                                windowBottom = it.boundsInWindow().bottom
                                safeBottom = windowBottom - paddingPx
                            }
                        ) { content() }
                    }
                }
            }
        }
        return scenario
    }

    private fun assertListEndIsSafe(listTag: String, lastItemTag: String) {
        device.waitForIdle()
        val list = requireNotNull(device.wait(Until.findObject(By.res(listTag)), 5_000))
        val bounds = list.visibleBounds
        assertEquals(
            "The list viewport must extend to the window bottom",
            windowBottom,
            bounds.bottom.toFloat(),
            1f
        )
        var previousBottom: Int? = null
        var reachedEnd = false
        repeat(20) {
            if (!reachedEnd) {
                device.swipe(
                    bounds.centerX(),
                    bounds.top + bounds.height() * 4 / 5,
                    bounds.centerX(),
                    bounds.top + bounds.height() / 5,
                    30
                )
                device.waitForIdle()
                val bottom = device.findObject(By.res(lastItemTag))?.visibleBounds?.bottom
                reachedEnd = bottom != null && bottom == previousBottom
                previousBottom = bottom
            }
        }
        assertTrue("The fixture must scroll to the last item", reachedEnd)
        val last = requireNotNull(device.wait(Until.findObject(By.res(lastItemTag)), 5_000))
        assertTrue("The complete last card must settle above navigation", last.visibleBounds.bottom <= safeBottom)
        assertTrue("The last card must remain in the viewport", last.visibleBounds.top >= bounds.top)
    }
}
