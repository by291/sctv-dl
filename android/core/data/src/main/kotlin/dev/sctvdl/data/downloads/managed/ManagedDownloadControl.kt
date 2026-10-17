package dev.sctvdl.data.downloads.managed

import dev.sctvdl.domain.download.DownloadTask

internal interface ManagedDownloadControl {
    suspend fun reconcile()

    suspend fun start()

    suspend fun stop(task: DownloadTask)

    suspend fun remove(task: DownloadTask)
}
