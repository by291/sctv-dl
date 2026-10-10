package dev.sctvdl.domain.repository

import kotlinx.coroutines.flow.Flow

interface FavouriteRepository {
    fun observeIds(): Flow<Set<String>>

    suspend fun toggle(id: String)
}
