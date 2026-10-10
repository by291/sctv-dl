package dev.sctvdl.data.favourites

import androidx.room.withTransaction
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.favourites.local.FavouriteEntity
import dev.sctvdl.domain.repository.FavouriteRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.map

internal class RoomFavouriteRepository @Inject constructor(private val database: SctvDatabase) : FavouriteRepository {
    override fun observeIds() = database.favourites().observeFavourites().map { it.toSet() }

    override suspend fun toggle(id: String) = database.withTransaction {
        val dao = database.favourites()
        if (dao.isFavourite(id)) dao.removeFavourite(id) else dao.addFavourite(FavouriteEntity(id))
    }
}
