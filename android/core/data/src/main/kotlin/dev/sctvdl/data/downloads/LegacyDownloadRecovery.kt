package dev.sctvdl.data.downloads

/** Existing platform jobs may be reconciled or cancelled; new submissions belong to managed transfers. */
internal interface LegacyDownloadRecovery {
    suspend fun reconcile()

    suspend fun cancel(taskId: String)
}
