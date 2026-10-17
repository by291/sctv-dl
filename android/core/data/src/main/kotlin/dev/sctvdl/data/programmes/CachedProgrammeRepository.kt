package dev.sctvdl.data.programmes

import dev.sctvdl.data.programmes.local.SnapshotStore
import dev.sctvdl.data.programmes.local.StoredSnapshot
import dev.sctvdl.data.programmes.remote.ProgrammeRemoteDataSource
import dev.sctvdl.data.programmes.remote.ProgrammeResponseParser
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.repository.ProgrammeRepository
import java.io.IOException
import java.time.Clock
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
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

internal class CachedProgrammeRepository(
    private val source: ProgrammeRemoteDataSource,
    private val store: SnapshotStore,
    private val parser: ProgrammeResponseParser,
    private val clock: Clock,
    private val dispatcher: CoroutineDispatcher
) : ProgrammeRepository {
    private data class RefreshState(val active: Boolean = false, val error: AppError? = null)

    private val states = ConcurrentHashMap<String, MutableStateFlow<RefreshState>>()
    private val versions = ConcurrentHashMap<String, AtomicLong>()
    private val writeLock = Mutex()
    private val cacheEpoch = AtomicLong()

    override suspend fun clearCache() = withContext(dispatcher) {
        writeLock.withLock {
            // Old responses and old error paths must not repopulate or dirty the cleared generation.
            cacheEpoch.incrementAndGet()
            store.clear()
            states.values.forEach { it.value = RefreshState() }
        }
    }

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
        { source.contents(programmeId, dateId) },
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
            val (ticket, epoch) = writeLock.withLock {
                state(key).value = RefreshState(active = true)
                version.incrementAndGet() to cacheEpoch.get()
            }

            try {
                val raw = fetch()
                // Validate before persisting; invalid responses must leave the previous snapshot intact.
                parse(raw)
                ensureActive()

                // Cancellation alone cannot reject a late response from an older refresh of the same key.
                writeLock.withLock {
                    if (ticket == version.get() &&
                        epoch == cacheEpoch.get()
                    ) {
                        store.put(StoredSnapshot(key, raw, clock.millis()))
                    }
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

                writeLock.withLock {
                    if (ticket == version.get() &&
                        epoch == cacheEpoch.get()
                    ) {
                        state(key).value = RefreshState(error = mapped)
                    }
                }
            } finally {
                withContext(NonCancellable) {
                    writeLock.withLock {
                        if (ticket == version.get() &&
                            epoch == cacheEpoch.get()
                        ) {
                            state(key).update { it.copy(active = false) }
                        }
                    }
                }
            }
        }
}
