package dev.sctvdl.app

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
import dev.sctvdl.design.ContentCard
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.ProgrammeContent
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
                    SctvTheme(AppSettings()) {
                        Column(Modifier.padding(16.dp)) {
                            ContentCard(
                                ProgrammeContent("full", "Full episode", standardUrl = "one.mp4"),
                                true,
                                false,
                                false,
                                { opened += "full" },
                                {}
                            )
                            ContentCard(
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
                    SctvTheme(AppSettings()) {
                        Column(Modifier.padding(16.dp)) {
                            ContentCard(
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
