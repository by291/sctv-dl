package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
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
import org.junit.Assert.assertNotNull
import org.junit.Test

class ProgrammeEntryTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun fullEpisodeAndClipOpenByTappingTheirTitles() {
        val opened = mutableListOf<String>()
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Column(Modifier.padding(16.dp)) {
                            EpisodeCard(
                                ProgrammeContent("full", "Full episode", standardUrl = "one.mp4"),
                                true,
                                false,
                                false,
                                { opened += "full" },
                                {}
                            )
                            EpisodeCard(
                                ProgrammeContent("clip", "Short clip", standardUrl = "two.mp4"),
                                false,
                                false,
                                false,
                                { opened += "clip" },
                                {}
                            )
                        }
                    }
                }
            }
            val full = device.wait(Until.findObject(By.text("Full episode")), 5_000)
            assertNotNull(full)
            full!!.click()
            requireNotNull(device.wait(Until.findObject(By.text("Short clip")), 5_000)).click()
            scenario.onActivity { assertEquals(listOf("full", "clip"), opened) }
        }
    }

    @Test fun missingMediaCannotOpenPlayback() {
        var opened = false
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Column(Modifier.padding(16.dp)) {
                            EpisodeCard(
                                ProgrammeContent("missing", "Missing media"),
                                false,
                                false,
                                false,
                                { opened = true },
                                {}
                            )
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.text("Missing media")), 5_000)).click()
            scenario.onActivity { assertEquals(false, opened) }
        }
    }
}
