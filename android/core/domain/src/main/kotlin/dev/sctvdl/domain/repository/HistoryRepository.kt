package dev.sctvdl.domain.repository

import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow

data class HistorySession(
    val key: ViewingKey,
    val deletionGeneration: Long,
    val sessionGeneration: Long,
    val previous: ViewingEntry?
)

enum class HistoryWriteResult { Saved, Invalidated }

/** Writes belong to the repository lifetime and remain ordered after the caller leaves playback. */
interface HistoryRepository {
    fun observeEntries(): Flow<List<ViewingEntry>>

    suspend fun begin(target: ViewingTarget): HistorySession

    fun submit(session: HistorySession, entry: ViewingEntry): Deferred<HistoryWriteResult>

    suspend fun remove(key: ViewingKey)

    suspend fun clear()
}
