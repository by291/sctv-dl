package dev.sctvdl.data

import dev.sctvdl.data.repository.decodeSettings
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.ThemeMode
import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsRepositoryTest {
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
