package dev.sctvdl.data.database

import androidx.room.withTransaction
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.data.history.local.UserMetadata
import javax.inject.Inject

internal class LegacyUserImport @Inject constructor(
    private val legacy: SctvDatabase,
    private val users: SctvUserDatabase
) {
    suspend fun ensureImported() = users.withTransaction {
        // The destination marker survives backup and makes restored deletions authoritative.
        if (users.history().metadata("legacy_favourites_imported") != null) return@withTransaction
        legacy.favourites().allIds().forEach { users.favourites().addFavourite(FavouriteEntity(it)) }
        users.history().putMetadata(UserMetadata("legacy_favourites_imported", "1"))
    }
}
