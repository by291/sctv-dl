package dev.sctvdl.app

import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Test

class CatalogueRestorationTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun favouriteToggleKeepsTheSearchAndRestoresItAfterRecreation() {
        val wifi = device.executeShellCommand("settings get global wifi_on").trim()
        val mobile = device.executeShellCommand("settings get global mobile_data").trim()
        try {
            device.executeShellCommand("svc wifi disable")
            device.executeShellCommand("svc data disable")
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val editable = By.clazz("android.widget.EditText")
                requireNotNull(device.wait(Until.findObject(By.desc("搜索栏目")), 5_000)).click()
                requireNotNull(device.wait(Until.findObject(editable), 5_000)).text = "catalogue-filter"
                requireNotNull(device.wait(Until.findObject(By.desc("只看收藏")), 5_000)).click()
                val favouritesSearch = device.wait(
                    Until.findObject(By.clazz("android.widget.EditText").text("catalogue-filter")),
                    5_000
                )
                assertNotNull("Toggling favourites must keep the current search", favouritesSearch)
                favouritesSearch!!.text = "favourites-filter"
                requireNotNull(device.wait(Until.findObject(By.desc("显示全部栏目")), 5_000)).click()
                assertNotNull(
                    device.wait(Until.findObject(By.clazz("android.widget.EditText").text("favourites-filter")), 5_000)
                )
                scenario.recreate()
                assertNotNull(
                    device.wait(Until.findObject(By.clazz("android.widget.EditText").text("favourites-filter")), 5_000)
                )
            }
        } finally {
            device.executeShellCommand("svc wifi ${if (wifi == "1") "enable" else "disable"}")
            device.executeShellCommand("svc data ${if (mobile == "1") "enable" else "disable"}")
        }
    }
}
