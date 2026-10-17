package dev.sctvdl.domain.testing

import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingKey
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.repository.HistoryRepository
import dev.sctvdl.domain.repository.HistorySession
import dev.sctvdl.domain.repository.HistoryWriteResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow

class FakeHistory : HistoryRepository {
    val entries = MutableStateFlow<List<ViewingEntry>>(emptyList())
    val writes = mutableListOf<ViewingEntry>()
    var fail = false
    private var generation = 0L

    override fun observeEntries() = entries

    override suspend fun begin(target: ViewingTarget): HistorySession {
        if (fail) error("Storage unavailable")
        return HistorySession(target.key, generation, ++generation, entries.value.find { it.key == target.key })
    }

    override fun submit(session: HistorySession, entry: ViewingEntry): CompletableDeferred<HistoryWriteResult> {
        if (fail) {
            return CompletableDeferred<HistoryWriteResult>().also {
                it.completeExceptionally(IllegalStateException("Disk full"))
            }
        }
        if (session.sessionGeneration != generation) return CompletableDeferred(HistoryWriteResult.Invalidated)
        writes += entry
        entries.value = listOf(entry) + entries.value.filter { it.key != entry.key }
        return CompletableDeferred(HistoryWriteResult.Saved)
    }

    override suspend fun remove(key: ViewingKey) {
        generation++
        entries.value = entries.value.filter { it.key != key }
    }

    override suspend fun clear() {
        generation++
        entries.value = emptyList()
    }
}
