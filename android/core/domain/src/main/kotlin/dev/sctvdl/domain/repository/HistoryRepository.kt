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
    /** Observe durable history in recency order. */
    fun observeEntries(): Flow<List<ViewingEntry>>

    /** Acquire a new session for this content and return its last saved entry. */
    suspend fun begin(target: ViewingTarget): HistorySession

    /** Queue progress, returning [HistoryWriteResult.Invalidated] if the session lost ownership. */
    fun submit(session: HistorySession, entry: ViewingEntry): Deferred<HistoryWriteResult>

    /** Remove an entry and invalidate the sessions that could recreate it. */
    suspend fun remove(key: ViewingKey)

    /** Invalidate open sessions before removing all entries in the same write. */
    suspend fun clear()
}
