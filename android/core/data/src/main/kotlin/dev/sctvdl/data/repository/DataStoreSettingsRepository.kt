package dev.sctvdl.data.repository

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import dev.sctvdl.domain.AppSettings
import dev.sctvdl.domain.SettingsRepository
import java.io.IOException
import javax.inject.Inject
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map

class DataStoreSettingsRepository @Inject constructor(private val store: DataStore<Preferences>) :
    SettingsRepository {
    private val keys = listOf(
        "theme",
        "quality",
        "dynamic",
        "wifi"
    ).associateWith(::stringPreferencesKey)

    override val settings = store.data.catch { error ->
        if (error is IOException) emit(emptyPreferences()) else throw error
    }.map { preferences -> decodeSettings(keys.mapValues { (_, key) -> preferences[key] }) }

    override suspend fun update(settings: AppSettings) {
        store.edit { preferences ->
            preferences[keys.getValue("theme")] = settings.theme.name
            preferences[keys.getValue("quality")] = settings.initialQuality.name
            preferences[keys.getValue("dynamic")] = settings.dynamicColour.toString()
            preferences[keys.getValue("wifi")] = settings.wifiOnlyDownloads.toString()
        }
    }
}
