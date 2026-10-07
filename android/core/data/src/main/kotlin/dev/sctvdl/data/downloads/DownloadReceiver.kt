package dev.sctvdl.data.downloads

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import dev.sctvdl.domain.DownloadRepository
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

@AndroidEntryPoint
class DownloadReceiver : BroadcastReceiver() {
    @Inject lateinit var repository: DownloadRepository

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == DownloadManager.ACTION_NOTIFICATION_CLICKED) {
            context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                context.startActivity(
                    it.addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    ).putExtra("open_downloads", true)
                )
            }
        } else if (intent.action == DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
            val pending = goAsync()
            CoroutineScope(Dispatchers.IO).launch {
                try {
                    repository.reconcile()
                } catch (
                    _: Exception
                ) { /* The next visible reconciliation retries the system query. */ } finally {
                    pending.finish()
                }
            }
        }
    }
}
