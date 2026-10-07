package dev.sctvdl.app

import dev.sctvdl.domain.BroadcastDate
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.FavouriteRepository
import dev.sctvdl.domain.Programme
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.ProgrammeRepository
import kotlinx.coroutines.flow.MutableStateFlow

class FakeProgrammes : ProgrammeRepository {
    val catalogue = MutableStateFlow(CachedResource<List<Programme>>())
    private val dates =
        mutableMapOf<String, MutableStateFlow<CachedResource<List<BroadcastDate>>>>()
    private val contents =
        mutableMapOf<String, MutableStateFlow<CachedResource<List<ProgrammeContent>>>>()
    val contentRequests = mutableListOf<Pair<String, String>>()
    override fun observeProgrammes() = catalogue
    override suspend fun refreshProgrammes() {}
    override fun observeDates(programmeId: String) = dates.getOrPut(programmeId) { MutableStateFlow(CachedResource()) }
    override suspend fun refreshDates(programmeId: String) {}
    override fun observeContents(programmeId: String, dateId: String) =
        contents.getOrPut("$programmeId:$dateId") { MutableStateFlow(CachedResource()) }
    override suspend fun refreshContents(programmeId: String, dateId: String) {
        contentRequests.add(programmeId to dateId)
    }
}
class FakeFavourites : FavouriteRepository {
    val ids = MutableStateFlow(emptySet<String>())
    override fun observeIds() = ids
    override suspend fun toggle(id: String) {
        ids.value =
            if (id in ids.value) ids.value - id else ids.value + id
    }
}
