package dev.sctvdl.feature.programmes.presentation

import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch

/** The screen owns the last accepted data and explicitly resubscribes after a failed read. */
internal fun <T> Flow<T>.onReadFailure(report: (AppError) -> Unit): Flow<T> = catch { failure ->
    if (failure is CancellationException) throw failure
    report(AppError(ErrorKind.Storage, "读取节目缓存失败，请重试"))
}
