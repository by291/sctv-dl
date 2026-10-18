package dev.sctvdl.feature.programmes.presentation

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.repository.FavouriteRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Retains confirmed membership on storage failure. Retrying a failed toggle uses the original programme ID. */
internal class FavouriteState(private val repository: FavouriteRepository, private val scope: CoroutineScope) {
    private val mutableIds = MutableStateFlow<Set<String>?>(null)
    val ids = mutableIds.asStateFlow()

    private val mutableError = MutableStateFlow<AppError?>(null)
    val error = mutableError.asStateFlow()

    private val writes = Mutex()
    private var observation: Job? = null
    private var failedToggleId: String? = null

    init {
        observe()
    }

    private fun observe() {
        if (observation?.isActive == true) return
        observation = scope.launch {
            try {
                repository.observeIds().collect {
                    mutableIds.value = it
                    if (failedToggleId == null) mutableError.value = null
                }
            } catch (failure: CancellationException) {
                throw failure
            } catch (_: Exception) {
                // Let catalogue data render even when the first membership read fails.
                if (mutableIds.value == null) mutableIds.value = emptySet()
                mutableError.value = AppError(ErrorKind.Storage, "无法读取收藏，请重试")
            }
        }
    }

    fun toggle(id: String) {
        scope.launch { writes.withLock { saveToggle(id) } }
    }

    private suspend fun saveToggle(id: String) {
        try {
            repository.toggle(id)
            failedToggleId = null
            mutableError.value = null
            observe()
        } catch (failure: CancellationException) {
            throw failure
        } catch (_: Exception) {
            failedToggleId = id
            mutableError.value = AppError(ErrorKind.Storage, "收藏未保存，请重试")
        }
    }

    fun retry() {
        observe()
        val id = failedToggleId ?: return
        scope.launch {
            writes.withLock {
                // Repeated retry taps must not toggle confirmed membership back after the first succeeds.
                if (failedToggleId == id) saveToggle(id)
            }
        }
    }
}
