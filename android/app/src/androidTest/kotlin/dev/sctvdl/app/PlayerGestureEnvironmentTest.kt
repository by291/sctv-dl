package dev.sctvdl.app

import android.content.Context
import android.media.AudioManager
import androidx.test.core.app.ActivityScenario
import dev.sctvdl.app.platform.ActivityPlaybackHost
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerGestureEnvironmentTest {
    @Test fun readingHintEligibilityDoesNotAcknowledgePresentation() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val preferences = activity.getSharedPreferences("player_gestures", Context.MODE_PRIVATE)
                val original = preferences.getBoolean("fullscreen_hint_seen", false)
                val environment = ActivityPlaybackHost(activity).gestureEnvironment
                try {
                    preferences.edit().putBoolean("fullscreen_hint_seen", false).commit()
                    assertTrue(environment.needsGestureHint())
                    assertTrue(environment.needsGestureHint())
                    environment.acknowledgeGestureHint()
                    assertTrue(!environment.needsGestureHint())
                } finally {
                    preferences.edit().putBoolean("fullscreen_hint_seen", original).commit()
                }
            }
        }
    }

    @Test fun brightnessRestoresTheEnteringWindowValueAndVolumeRetainsNativeChanges() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val host = ActivityPlaybackHost(activity)
                val environment = host.gestureEnvironment
                val originalBrightness = activity.window.attributes.screenBrightness
                val audio = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val stream = AudioManager.STREAM_MUSIC
                val originalVolume = audio.getStreamVolume(stream)
                val maximum = audio.getStreamMaxVolume(stream)
                try {
                    activity.window.attributes = activity.window.attributes.apply { screenBrightness = 0.4f }
                    environment.captureBrightness()
                    assertEquals(65, environment.adjustBrightness(0.25f))
                    environment.restoreBrightness()
                    assertEquals(0.4f, activity.window.attributes.screenBrightness)

                    audio.setStreamVolume(stream, maximum / 2, 0)
                    repeat(100) { environment.adjustVolume(0.01f) }
                    assertEquals(maximum, audio.getStreamVolume(stream))
                    audio.setStreamVolume(stream, 0, 0)
                    assertTrue(environment.adjustVolume(0.25f) in 1..30)
                    val changed = audio.getStreamVolume(stream)
                    host.fullscreen(false)
                    assertEquals(changed, audio.getStreamVolume(stream))
                } finally {
                    audio.setStreamVolume(stream, originalVolume, 0)
                    activity.window.attributes = activity.window.attributes.apply {
                        screenBrightness = originalBrightness
                    }
                }
            }
        }
    }
}
