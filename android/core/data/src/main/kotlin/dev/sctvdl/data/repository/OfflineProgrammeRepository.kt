package dev.sctvdl.data.repository

import dev.sctvdl.data.network.UpstreamParser
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.AppException
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.ProgrammeRepository
import java.io.IOException
import java.time.Clock
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import retrofit2.HttpException

class OfflineProgrammeRepository(
    private val source: ProgrammeSource,
    private val store: SnapshotStore,
    private val parser: UpstreamParser,
    private val clock: Clock,
    private val dispatcher: CoroutineDispatcher
) : ProgrammeRepository {
    private data class RefreshState(val active: Boolean = false, val error: AppError? = null)
    private val states = ConcurrentHashMap<String, MutableStateFlow<RefreshState>>()
    private val versions = ConcurrentHashMap<String, AtomicLong>()
    private val writeLock = Mutex()

    override fun observeProgrammes() = observe("programmes", parser::programmes)
    override suspend fun refreshProgrammes() = refresh(
        "programmes",
        source::programmes,
        parser::programmes
    )
    override fun observeDates(programmeId: String) = observe("dates:$programmeId", parser::dates)
    override suspend fun refreshDates(programmeId: String) = refresh(
        "dates:$programmeId",
        { source.dates(programmeId) },
        parser::dates
    )
    override fun observeContents(programmeId: String, dateId: String) = observe(
        "contents:$programmeId:$dateId",
        parser::contents
    )
    override suspend fun refreshContents(programmeId: String, dateId: String) = refresh(
        "contents:$programmeId:$dateId",
        {
            source.contents(
                programmeId,
                dateId
            )
        },
        parser::contents
    )

    private fun state(key: String) = states.getOrPut(key) { MutableStateFlow(RefreshState()) }

    private fun <T> observe(key: String, parse: (String) -> T): Flow<CachedResource<T>> = combine(
        store.observe(key),
        state(key)
    ) {
            snapshot,
            refresh
        ->
        try {
            CachedResource(
                snapshot?.let { parse(it.payload) },
                refresh.active,
                refresh.error,
                snapshot?.let { Instant.ofEpochMilli(it.updatedAt) }
            )
        } catch (error: AppException) {
            CachedResource<T>(isRefreshing = refresh.active, error = refresh.error ?: error.error)
        }
    }.flowOn(dispatcher)

    private suspend fun <T> refresh(key: String, fetch: suspend () -> String, parse: (String) -> T) =
        withContext(dispatcher) {
            val version = versions.getOrPut(key) { AtomicLong() }
            val ticket = version.incrementAndGet()
            state(key).value = RefreshState(active = true)

            try {
                val raw = fetch()
                parse(raw)
                ensureActive()
                writeLock.withLock {
                    if (ticket == version.get()) store.put(StoredSnapshot(key, raw, clock.millis()))
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val mapped = when (error) {
                    is AppException -> error.error
                    is HttpException -> AppError(
                        ErrorKind.Http,
                        "节目服务请求失败（${error.code()}）",
                        error.code()
                    )
                    is IOException -> AppError(ErrorKind.Network, "网络连接失败，请检查网络后重试")
                    else -> AppError(ErrorKind.Storage, "暂时无法保存节目数据")
                }
                if (ticket == version.get()) state(key).value = RefreshState(error = mapped)
            } finally {
                if (ticket == version.get()) state(key).update { it.copy(active = false) }
            }
        }
}
