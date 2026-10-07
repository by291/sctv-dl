package dev.sctvdl.domain

import kotlinx.coroutines.flow.Flow

interface ProgrammeRepository {
    fun observeProgrammes(): Flow<CachedResource<List<Programme>>>
    suspend fun refreshProgrammes()
    fun observeDates(programmeId: String): Flow<CachedResource<List<BroadcastDate>>>
    suspend fun refreshDates(programmeId: String)
    fun observeContents(programmeId: String, dateId: String): Flow<CachedResource<List<ProgrammeContent>>>
    suspend fun refreshContents(programmeId: String, dateId: String)
}
interface FavouriteRepository {
    fun observeIds(): Flow<Set<String>>
    suspend fun toggle(id: String)
}
interface SettingsRepository {
    val settings: Flow<AppSettings>
    suspend fun update(settings: AppSettings)
}
interface DownloadRepository {
    fun observeTasks(): Flow<List<DownloadTask>>
    suspend fun enqueue(requests: List<DownloadRequest>): BatchDownloadResult
    suspend fun cancel(taskId: String)
    suspend fun retry(taskId: String): BatchDownloadResult
    suspend fun removeRecord(taskId: String)
    suspend fun reconcile()
}
