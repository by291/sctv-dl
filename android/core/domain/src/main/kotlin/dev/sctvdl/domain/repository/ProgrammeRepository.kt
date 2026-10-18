package dev.sctvdl.domain.repository

import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import kotlinx.coroutines.flow.Flow

/**
 * Observes persisted snapshots with refresh status, independently keyed by programme and broadcast date.
 * Refresh failures retain cached data, and a validated empty response is still a successful snapshot.
 * Refreshes propagate coroutine cancellation and reject responses superseded by a newer request of the same key.
 */
interface ProgrammeRepository {
    suspend fun clearCache()

    fun observeProgrammes(): Flow<CachedResource<List<Programme>>>

    suspend fun refreshProgrammes()

    fun observeDates(programmeId: String): Flow<CachedResource<List<BroadcastDate>>>

    suspend fun refreshDates(programmeId: String)

    fun observeContents(programmeId: String, dateId: String): Flow<CachedResource<List<ProgrammeContent>>>

    suspend fun refreshContents(programmeId: String, dateId: String)
}
