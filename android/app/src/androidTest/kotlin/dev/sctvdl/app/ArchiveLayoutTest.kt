package dev.sctvdl.app

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.features.archive.ArchiveScreen
import dev.sctvdl.app.features.archive.ArchiveUiState
import dev.sctvdl.design.SctvTheme
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class ArchiveLayoutTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun recentDateShortcutSwitchesBroadcastWithoutOpeningASheet() {
        val latest = BroadcastDate("latest", LocalDate.of(2026, 10, 6))
        val older = BroadcastDate("older", LocalDate.of(2026, 10, 5))
        var state by mutableStateOf(
            ArchiveUiState(
                programmeId = "1",
                programme = Programme("1", "四川新闻联播", null, 0),
                dates = CachedResource(listOf(latest, older)),
                date = latest,
                contents = CachedResource(listOf(ProgrammeContent("clip", "今日新闻片段", standardUrl = "one.mp4")))
            )
        )
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvTheme(AppSettings()) {
                        ArchiveScreen(state, false, {
                        }, { state = state.copy(date = it) }, {}, {}, {}, {}, {}, {}, {}, {}, {})
                    }
                }
            }
            val shortcut = device.wait(Until.findObject(By.desc("回看2026-10-05")), 5_000)
            assertNotNull("Recent broadcasts must be selectable directly in the archive", shortcut)
            shortcut!!.click()
            scenario.onActivity { assertEquals("older", state.date?.id) }
            requireNotNull(device.wait(Until.findObject(By.text("更多日期")), 5_000)).click()
            assertNotNull(device.wait(Until.findObject(By.text("选择播出日期")), 5_000))
        }
    }
}
