package dev.sctvdl.data.downloads.managed

import android.app.job.JobParameters
import android.app.job.JobService
import android.util.Log
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@AndroidEntryPoint
class ManagedDownloadJobService : JobService() {
    @Inject internal lateinit var runtime: ManagedTransferRuntime

    private data class Running(val lease: ExecutionLease, val work: Job)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val running = mutableMapOf<Int, Running>()

    override fun onStartJob(params: JobParameters): Boolean {
        val owner = when (params.jobId) {
            DownloadRecoveryScheduler.WIFI -> ExecutionOwner.WifiJob
            DownloadRecoveryScheduler.LOCAL -> ExecutionOwner.LocalJob
            else -> ExecutionOwner.UnrestrictedJob
        }
        val lease = runtime.acquire(owner)
        val work = scope.launch(start = CoroutineStart.LAZY) {
            try {
                do {
                    runtime.reconcile()
                    if (!runtime.hasWork(owner)) break
                    delay(1000)
                } while (true)
                running.remove(params.jobId)
                jobFinished(params, runtime.hasPending(owner))
            } catch (failure: CancellationException) {
                throw failure
            } catch (failure: Exception) {
                Log.e("ManagedDownloads", "Scheduled reconciliation failed", failure)
                running.remove(params.jobId)
                jobFinished(params, true)
            } finally {
                lease.close()
            }
        }
        running[params.jobId] = Running(lease, work)
        work.start()
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        running.remove(params.jobId)?.let {
            it.lease.close()
            it.work.cancel()
        }
        return true
    }

    override fun onDestroy() {
        running.values.forEach { it.lease.close() }
        running.clear()
        scope.cancel()
        super.onDestroy()
    }
}
