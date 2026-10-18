package dev.sctvdl.feature.settings

import dev.sctvdl.domain.repository.CacheCleanupResult
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.domain.repository.StorageMaintenance
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.domain.testing.FakeHistory
import dev.sctvdl.domain.testing.MainDispatcherRule
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun failedPreferenceWriteRetainsSavedValuesAndAllowsAnotherAttempt() = runTest {
        var fail = true
        val values = MutableStateFlow(AppSettings(theme = ThemeMode.Light))
        val repository = object : SettingsRepository {
            override val settings = values

            override suspend fun update(settings: AppSettings) {
                if (fail) throw IOException("Storage unavailable")
                values.value = settings
            }
        }
        val storage = object : StorageMaintenance {
            override suspend fun clearCache() = CacheCleanupResult(true, true)
        }
        val model = SettingsViewModel(repository, FakeHistory(), storage)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        model.setTheme(ThemeMode.Dark)
        runCurrent()
        assertEquals(ThemeMode.Light, model.uiState.value.theme)

        assertNotNull(model.error.value)

        fail = false
        model.retry()
        runCurrent()
        assertEquals(ThemeMode.Dark, model.uiState.value.theme)
        assertNull(model.error.value)
    }

    @Test fun failedObservationRetainsConfirmedSettingsAndRetryResubscribes() = runTest {
        val values = MutableStateFlow(AppSettings(theme = ThemeMode.Light))
        var fail = true
        val repository = object : SettingsRepository {
            override val settings = flow {
                emit(values.value)
                if (fail) throw IOException("Read failed")
                emitAll(values)
            }

            override suspend fun update(settings: AppSettings) {
                values.value = settings
            }
        }
        val storage = object : StorageMaintenance {
            override suspend fun clearCache() = CacheCleanupResult(true, true)
        }
        val model = SettingsViewModel(repository, FakeHistory(), storage)
        runCurrent()

        assertEquals(ThemeMode.Light, model.uiState.value.theme)
        assertNotNull(model.error.value)

        fail = false
        values.value = AppSettings(theme = ThemeMode.Dark)
        model.retry()
        runCurrent()

        assertEquals(ThemeMode.Dark, model.uiState.value.theme)
        assertNull(model.error.value)
    }

    @Test fun cancelledWriteDoesNotBecomeARetryableStorageFailure() = runTest {
        val repository = object : SettingsRepository {
            override val settings = MutableStateFlow(AppSettings(theme = ThemeMode.Light))

            override suspend fun update(settings: AppSettings): Unit = throw CancellationException("Destination left")
        }
        val storage = object : StorageMaintenance {
            override suspend fun clearCache() = CacheCleanupResult(true, true)
        }
        val model = SettingsViewModel(repository, FakeHistory(), storage)
        runCurrent()

        model.setTheme(ThemeMode.Dark)
        runCurrent()

        assertEquals(ThemeMode.Light, model.uiState.value.theme)
        assertNull(model.error.value)
    }
}
