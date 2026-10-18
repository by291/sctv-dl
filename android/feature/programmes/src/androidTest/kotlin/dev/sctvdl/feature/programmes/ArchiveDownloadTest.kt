package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.download.DownloadRequest
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.archive.ArchiveScreen
import dev.sctvdl.feature.programmes.archive.ArchiveUiState
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class ArchiveDownloadTest {
    @Test fun confirmationPreservesAcceptedProgrammeContextForLocalPlaybackAndArtwork() {
        val programme = Programme("1", "Accepted programme", "accepted-cover.jpg", 0)
        val date = BroadcastDate("2", LocalDate.of(2026, 10, 18))
        val content = ProgrammeContent("3", "Accepted clip", standardUrl = "https://fscgc.scgchc.com/fixture.mp4")
        val state = ArchiveUiState(
            programmeId = "1",
            programme = programme,
            date = date,
            dates = CachedResource(listOf(date)),
            contents = CachedResource(listOf(content)),
            selectedIds = setOf("3"),
            selectionMode = true,
            hasUpdate = true
        )
        val requests = mutableListOf<DownloadRequest>()
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        ArchiveScreen(state, true, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, requests::addAll)
                    }
                }
            }

            requireNotNull(device.wait(Until.findObject(By.text("下载所选（1）")), 5_000)).click()
            requireNotNull(device.wait(Until.findObject(By.text(Quality.Standard.label)), 5_000)).click()
            device.waitForIdle()

            scenario.onActivity {
                val request = requests.single()
                assertEquals(Quality.Standard, request.requestedQuality)
                assertEquals(true, request.wifiOnly)
                assertNotNull("Screen confirmation must retain accepted context", request.selection)
                assertEquals(programme, request.selection?.programme)
                assertEquals(date, request.selection?.broadcast)
                assertEquals(content, request.selection?.content)
            }
        }
    }
}
