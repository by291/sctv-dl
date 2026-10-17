package dev.sctvdl.data.downloads.managed

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Only explicit user starts enter this host; jobs execute in their own JobService lifetime. */
@AndroidEntryPoint
class ManagedDownloadService : Service() {
    @Inject internal lateinit var runtime: ManagedTransferRuntime
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var work: Job? = null
    private var lease: ExecutionLease? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(ManagedDownloadNotifications.ID, ManagedDownloadNotifications.create(this))
        wakeLock =
            getSystemService(
                PowerManager::class.java
            ).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sctv:downloads").apply {
                setReferenceCounted(false)
            }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (work?.isActive != true) {
            val executionLease = runtime.acquire(ExecutionOwner.Foreground)
            lease = executionLease
            work = scope.launch(Dispatchers.IO) {
                try {
                    do {
                        if (wakeLock?.isHeld != true) wakeLock?.acquire(10 * 60_000L)
                        runtime.reconcile()
                        if (!runtime.hasWork(ExecutionOwner.Foreground)) break
                        delay(1000)
                    } while (true)
                } catch (failure: CancellationException) {
                    throw failure
                } catch (failure: Exception) {
                    // Durable jobs remain responsible for retry after a transient host/store failure.
                    Log.e("ManagedDownloads", "Foreground reconciliation failed", failure)
                } finally {
                    executionLease.close()
                    lease = null
                    if (wakeLock?.isHeld == true) wakeLock?.release()
                    stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Respect the OS execution budget; persisted jobs may recover later, never an immediate FGS restart loop.
        work?.cancel()
        lease?.close()
        lease = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        stopSelf()
    }

    override fun onDestroy() {
        scope.cancel()
        lease?.close()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
