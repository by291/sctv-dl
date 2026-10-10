package dev.sctvdl.data.settings

import dev.sctvdl.data.settings.decodeSettings
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsPreferencesTest {
    @Test fun missingAndInvalidPreferencesUseSafeDefaults() {
        assertEquals(AppSettings(), decodeSettings(emptyMap()))
        assertEquals(
            AppSettings(),
            decodeSettings(
                mapOf(
                    "theme" to "purple",
                    "quality" to "4K",
                    "dynamic" to "maybe",
                    "wifi" to "maybe"
                )
            )
        )
    }

    @Test fun validPreferencesRoundTripIndependently() {
        assertEquals(
            AppSettings(ThemeMode.Dark, true, Quality.Smooth, true),
            decodeSettings(
                mapOf(
                    "theme" to "Dark",
                    "quality" to "Smooth",
                    "dynamic" to "true",
                    "wifi" to "true"
                )
            )
        )
    }
}
