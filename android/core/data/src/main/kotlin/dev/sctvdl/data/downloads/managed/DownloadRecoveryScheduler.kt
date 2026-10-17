package dev.sctvdl.data.downloads.managed

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.sctvdl.data.downloads.local.DownloadStore
import dev.sctvdl.domain.download.DownloadOwner
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.isActive
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
internal class DownloadRecoveryScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val store: DownloadStore
) {
    suspend fun reconcile() {
        val tasks = store.all().filter { it.owner == DownloadOwner.Media3 }
        val scheduler = context.getSystemService(JobScheduler::class.java)
        val desired = mapOf(
            ANY to tasks.any { it.state.isActive && !it.userPaused && !it.cacheComplete && !it.wifiOnly },
            WIFI to tasks.any { it.state.isActive && !it.userPaused && !it.cacheComplete && it.wifiOnly },
            LOCAL to tasks.any { it.cleanupPending || it.state == DownloadState.Finalizing }
        )
        desired.forEach { (id, needed) ->
            if (!needed) {
                scheduler.cancel(id)
            } else if (scheduler.getPendingJob(id) == null) {
                val builder = JobInfo.Builder(id, ComponentName(context, ManagedDownloadJobService::class.java))
                    .setPersisted(true).setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                when (id) {
                    ANY -> builder.setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setMinimumLatency(30_000)
                    WIFI -> builder.setMinimumLatency(30_000).setRequiredNetwork(
                        NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build()
                    )
                    LOCAL -> builder.setMinimumLatency(1000)
                }
                check(scheduler.schedule(builder.build()) == JobScheduler.RESULT_SUCCESS) {
                    "Download recovery scheduling rejected"
                }
            }
        }
    }

    companion object {
        const val ANY = 2401
        const val WIFI = 2402
        const val LOCAL = 2403
    }
}
