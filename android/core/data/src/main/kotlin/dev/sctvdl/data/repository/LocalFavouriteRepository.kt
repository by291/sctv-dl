package dev.sctvdl.data.repository

import androidx.room.withTransaction
import dev.sctvdl.data.local.FavouriteEntity
import dev.sctvdl.data.local.SctvDatabase
import dev.sctvdl.domain.FavouriteRepository
import javax.inject.Inject
import kotlinx.coroutines.flow.map

class LocalFavouriteRepository @Inject constructor(private val database: SctvDatabase) : FavouriteRepository {
    override fun observeIds() = database.programmes().observeFavourites().map { it.toSet() }

    override suspend fun toggle(id: String) = database.withTransaction {
        val dao = database.programmes()
        if (dao.isFavourite(id)) dao.removeFavourite(id) else dao.addFavourite(FavouriteEntity(id))
    }
}
