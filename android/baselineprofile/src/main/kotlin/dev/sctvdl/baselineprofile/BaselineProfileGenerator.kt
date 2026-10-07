package dev.sctvdl.baselineprofile

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test

class BaselineProfileGenerator {
    @get:Rule val profile = BaselineProfileRule()

    @Test
    fun startup() = profile.collect("dev.sctvdl.app", includeInStartupProfile = true) {
        pressHome()
        startActivityAndWait()
        assertNotNull(device.wait(Until.findObject(By.res("catalogue-grid")), 20_000))
    }

    @Test
    fun catalogueArchiveAndPlayer() = profile.collect("dev.sctvdl.app") {
        pressHome()
        startActivityAndWait()
        val programme = device.wait(Until.findObject(By.res("programme-1")), 20_000)
        assertNotNull("Programme service must be reachable or cached", programme)
        programme.click()
        val play = device.wait(Until.findObject(By.text("播放")), 20_000)
        assertNotNull("Archive must contain a playable broadcast", play)
        play.click()
        assertNotNull(device.wait(Until.findObject(By.desc("开始播放")), 20_000))
        device.pressBack()
    }
}
