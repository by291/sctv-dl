package dev.sctvdl.data.favourites

import androidx.room.withTransaction
import dev.sctvdl.data.database.LegacyUserImport
import dev.sctvdl.data.database.SctvUserDatabase
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.domain.repository.FavouriteRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map

internal class RoomFavouriteRepository @Inject constructor(
    private val database: SctvUserDatabase,
    private val legacyImport: LegacyUserImport
) : FavouriteRepository {
    override fun observeIds() = flow {
        legacyImport.ensureImported()
        emitAll(database.favourites().observeFavourites().map { it.toSet() })
    }

    override suspend fun toggle(id: String) {
        legacyImport.ensureImported()
        database.withTransaction {
            val dao = database.favourites()
            if (dao.isFavourite(id)) dao.removeFavourite(id) else dao.addFavourite(FavouriteEntity(id))
        }
    }
}
