package dev.sctvdl.data.network

import android.content.SharedPreferences
import java.io.IOException
import java.util.UUID

/** Retains the upstream device identity across process restarts and concurrent first requests. */
internal class InstallationDeviceId(private val preferences: SharedPreferences) {
    fun getOrCreate(): String = synchronized(preferences) {
        preferences.getString("device_id", null)?.let { return@synchronized it }

        val deviceId = UUID.randomUUID().toString()
        if (!preferences.edit().putString("device_id", deviceId).commit()) {
            throw IOException("Unable to persist the upstream device identity")
        }

        deviceId
    }
}
