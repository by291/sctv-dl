package dev.sctvdl.data.history

import androidx.room.withTransaction
import dev.sctvdl.data.database.SctvUserDatabase
import dev.sctvdl.data.history.local.HistoryEntity
import dev.sctvdl.data.history.local.HistorySessionEntity
import dev.sctvdl.data.history.local.ViewingTargetCodec
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.history.isViewingCompleted
import dev.sctvdl.domain.repository.HistoryRepository
import dev.sctvdl.domain.repository.HistorySession
import dev.sctvdl.domain.repository.HistoryWriteResult
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

internal class RoomHistoryRepository(private val database: SctvUserDatabase, scope: CoroutineScope) :
    HistoryRepository {
    private val owner = scope.coroutineContext[Job]
    private val commands = Channel<suspend () -> Unit>(Channel.UNLIMITED)
    private val dao = database.history()

    init {
        // All operations share a FIFO queue, including clear/remove and navigation session replacement.
        // The application scope owns this writer; leaving a player never cancels its final snapshot.
        scope.launch { for (command in commands) command() }.invokeOnCompletion { commands.cancel() }
    }

    override fun observeEntries() = dao.observe().map { entries -> entries.map { it.toEntry() } }

    override suspend fun begin(target: ViewingTarget): HistorySession = enqueue {
        database.withTransaction {
            val key = ViewingTargetCodec.key(target.key)
            val previous = dao.session(key) ?: HistorySessionEntity(key)
            val current = previous.copy(sessionGeneration = previous.sessionGeneration + 1)
            dao.putSession(current)
            HistorySession(target.key, current.deletionGeneration, current.sessionGeneration, dao.get(key)?.toEntry())
        }
    }.await()

    override fun submit(session: HistorySession, entry: ViewingEntry): Deferred<HistoryWriteResult> = enqueue {
        database.withTransaction {
            val key = ViewingTargetCodec.key(entry.key)
            val current = dao.session(key)
            if (entry.key != session.key || current?.deletionGeneration != session.deletionGeneration ||
                current.sessionGeneration != session.sessionGeneration
            ) {
                return@withTransaction HistoryWriteResult.Invalidated
            }

            val duration = entry.durationMs?.takeIf { it > 0 }
            val position = entry.positionMs.coerceAtLeast(0).let {
                if (duration ==
                    null
                ) {
                    it
                } else {
                    it.coerceAtMost(duration)
                }
            }
            dao.put(
                HistoryEntity(
                    key,
                    ViewingTargetCodec.encode(entry.target),
                    position,
                    duration,
                    entry.viewedAt.toEpochMilli(),
                    isViewingCompleted(position, duration, entry.completed)
                )
            )
            dao.trim()
            HistoryWriteResult.Saved
        }
    }

    override suspend fun remove(key: ViewingKey) = enqueue {
        database.withTransaction {
            val encoded = ViewingTargetCodec.key(key)
            val current = dao.session(encoded) ?: HistorySessionEntity(encoded)
            dao.putSession(current.copy(deletionGeneration = current.deletionGeneration + 1))
            dao.remove(encoded)
        }
    }.await()

    override suspend fun clear() = enqueue {
        database.withTransaction {
            dao.invalidateAll()
            dao.clear()
        }
    }.await()

    private fun <T> enqueue(action: suspend () -> T): Deferred<T> {
        val result = CompletableDeferred<T>(owner)
        val sent = commands.trySend {
            try {
                result.complete(action())
            } catch (failure: CancellationException) {
                result.cancel(failure)
                throw failure
            } catch (failure: Exception) {
                result.completeExceptionally(failure)
            }
        }
        if (sent.isFailure) result.completeExceptionally(IllegalStateException("History writer unavailable"))
        return result
    }

    private fun HistoryEntity.toEntry() = ViewingEntry(
        ViewingTargetCodec.decode(targetJson),
        positionMs,
        durationMs,
        Instant.ofEpochMilli(viewedAt),
        completed
    )
}
