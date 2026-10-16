package dev.sctvdl.app

import android.graphics.Rect
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PrimaryTopBarTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)

    @Test fun primaryDestinationsAndSearchKeepTheSameToolbarHeight() {
        val resources = instrumentation.targetContext.resources
        val heightDp = if (resources.configuration.fontScale >= 1.5f) 88 else 64
        val heightPx = (heightDp * resources.displayMetrics.density).roundToInt()

        ActivityScenario.launch(MainActivity::class.java).use {
            val catalogue = toolbarBounds(await(By.text("sctv-dl")))
            assertEquals("The library must use the primary toolbar height", heightPx, catalogue.height())

            await(By.res("filter-favourites")).click()
            assertEquals(catalogue, toolbarBounds(await(By.text("sctv-dl"))))
            await(By.res("filter-all")).click()
            await(By.desc("搜索栏目")).click()
            assertEquals(
                "Opening search must keep the toolbar height when keyboard insets change",
                heightPx,
                toolbarBounds(await(By.desc("退出搜索"))).height()
            )
            assertTrue("Search must focus its input", await(By.clazz("android.widget.EditText")).isFocused)
            await(By.desc("退出搜索")).click()
            assertEquals(catalogue, toolbarBounds(await(By.text("sctv-dl"))))

            await(By.res("tab-Downloads")).click()
            assertEquals("Downloads must align with the library", catalogue, toolbarBounds(await(By.desc("系统下载"))))
            await(By.res("tab-Settings")).click()
            await(By.text("显示模式"))
            val heading = device.wait(Until.findObjects(By.text("设置")), 5_000).minBy { node ->
                node.visibleBounds.top
            }
            assertEquals("Settings must align with the library", catalogue, toolbarBounds(heading))

            await(By.res("tab-Catalogue")).click()
            assertEquals(
                "Returning to the library must preserve its toolbar",
                catalogue,
                toolbarBounds(await(By.text("sctv-dl")))
            )
        }
    }

    private fun await(selector: BySelector): UiObject2 = requireNotNull(device.wait(Until.findObject(selector), 5_000))

    private fun toolbarBounds(child: UiObject2): Rect {
        device.waitForIdle()
        val density = instrumentation.targetContext.resources.displayMetrics.density
        var node: UiObject2? = child
        var toolbar: Rect? = null
        while (node != null) {
            val bounds = node.visibleBounds
            if (bounds.height() in (48 * density).roundToInt()..(120 * density).roundToInt()) {
                if (toolbar == null || bounds.width() > toolbar.width()) toolbar = bounds
            }
            node = node.parent
        }
        return requireNotNull(toolbar) { "No compact toolbar ancestor found" }
    }
}
