package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.archive.components.EpisodeCard
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ContentSelectionTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun batchSelectionUsesTheWholeCardForFullEpisodesAndClips() {
        val full = ProgrammeContent("full", "Full episode", standardUrl = "one.mp4")
        val clip = ProgrammeContent("clip", "News clip", standardUrl = "two.mp4")
        val selected = mutableListOf<String>()
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Column(Modifier.width(320.dp).padding(16.dp)) {
                            EpisodeCard(full, true, true, false, {}, { selected += full.id })
                            EpisodeCard(clip, false, true, false, {}, { selected += clip.id })
                        }
                    }
                }
            }
            val fullTarget = requireNotNull(device.wait(Until.findObject(By.desc("选择Full episode")), 5_000))
            val clipTarget = requireNotNull(device.wait(Until.findObject(By.desc("选择News clip")), 5_000))
            assertTrue(
                "Selection must include the title and image, not a small trailing checkbox",
                fullTarget.visibleBounds.width() > device.displayWidth / 2
            )
            assertEquals(
                "Both card types must share the leading selection edge",
                fullTarget.visibleBounds.left,
                clipTarget.visibleBounds.left
            )
            fullTarget.click()
            clipTarget.click()
            scenario.onActivity { assertEquals(listOf("full", "clip"), selected) }
        }
    }

    @Test fun contentWithoutMediaCannotBeSelectedByTappingItsCard() {
        var selected = false
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        EpisodeCard(
                            ProgrammeContent("missing", "Missing video"),
                            false,
                            true,
                            false,
                            {},
                            { selected = true }
                        )
                    }
                }
            }
            val target = device.wait(Until.findObject(By.desc("选择Missing video")), 5_000)
            assertNotNull(target)
            assertFalse(requireNotNull(device.findObject(By.checkable(true))).isEnabled)
            target!!.click()
            scenario.onActivity { assertFalse(selected) }
        }
    }
}
