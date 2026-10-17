package dev.sctvdl.data.downloads.managed

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

internal object ManagedDownloadNotifications {
    const val ID = 2400
    private const val CHANNEL = "managed_downloads"

    fun create(context: Context): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "视频下载", NotificationManager.IMPORTANCE_LOW))
        val intent = requireNotNull(context.packageManager.getLaunchIntentForPackage(context.packageName))
            .addFlags(
                Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            ).putExtra("open_downloads", true)
        return Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("蜀台回看 · 视频下载")
            .setContentText("正在下载或保存视频，点击查看进度")
            .setContentIntent(
                PendingIntent.getActivity(
                    context,
                    ID,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            .setOngoing(true).setOnlyAlertOnce(true).setProgress(0, 0, true).build()
    }
}
