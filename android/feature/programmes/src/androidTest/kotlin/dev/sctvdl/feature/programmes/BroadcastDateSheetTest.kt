package dev.sctvdl.feature.programmes

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
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.archive.BroadcastDateSheet
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BroadcastDateSheetTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun choosingAnAvailableDateFromAnotherMonthReturnsItsIdentityAndDismisses() {
        val latest = BroadcastDate("latest", LocalDate.of(2026, 10, 9))
        val older = BroadcastDate("previous-month", LocalDate.of(2026, 9, 30))
        var selected: BroadcastDate? = null
        var visible by mutableStateOf(true)
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        if (visible) {
                            BroadcastDateSheet(
                                listOf(latest, older),
                                latest.id,
                                { selected = it },
                                { visible = false }
                            )
                        }
                    }
                }
            }
            requireNotNull(device.wait(Until.findObject(By.textStartsWith("9月30日")), 5_000)).click()
            assertTrue(device.wait(Until.gone(By.text("选择播出日期")), 5_000))
            scenario.onActivity { assertEquals(older, selected) }
        }
    }
}
