package dev.sctvdl.data.settings

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Test

private const val PERSISTENCE_TIMEOUT_MS = 10_000L

class SettingsPersistenceTest {
    @Test fun changedSettingsSurviveDataStoreReopening(): Unit = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val file = context.cacheDir.resolve("settings-${UUID.randomUUID()}.preferences_pb")
        val changed = AppSettings(
            theme = ThemeMode.Dark,
            dynamicColour = true,
            initialQuality = Quality.Smooth,
            wifiOnlyDownloads = true
        )

        try {
            withTimeout(PERSISTENCE_TIMEOUT_MS) {
                withSettings(file) { repository ->
                    assertEquals(AppSettings(), repository.settings.first())
                    repository.update(changed)
                }

                withSettings(file) { reopened ->
                    assertEquals(changed, reopened.settings.first())
                }
            }
        } finally {
            file.delete()
        }
    }

    private suspend fun withSettings(file: File, exercise: suspend (SettingsRepository) -> Unit) {
        val owner = SupervisorJob()
        val scope = CoroutineScope(Dispatchers.IO + owner)
        val store = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })

        try {
            exercise(DataStoreSettingsRepository(store))
        } finally {
            // DataStore releases the file registration when its scope finishes.
            withContext(NonCancellable) { owner.cancelAndJoin() }
        }
    }
}
