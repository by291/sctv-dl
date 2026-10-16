package dev.sctvdl.flutter

import android.content.Intent
import com.bbflight.background_downloader.NotificationReceiver
import org.json.JSONObject

/** An acknowledgement for an older tap cannot consume a newer launch intent. */
internal fun consumeDownloadNotificationIntent(current: Intent, taskId: String?): Intent? {
    if (taskId == null || current.action != NotificationReceiver.actionTap) return null
    val receivedId = runCatching {
        JSONObject(current.getStringExtra(NotificationReceiver.keyTask) ?: "").optString("taskId")
    }.getOrNull()
    if (receivedId != taskId) return null
    return Intent(current).apply {
        action = Intent.ACTION_MAIN
        listOf(
            NotificationReceiver.keyTask,
            NotificationReceiver.keyTaskId,
            NotificationReceiver.keyBundle,
            NotificationReceiver.keyGroupNotificationName,
            NotificationReceiver.keyNotificationConfig,
            NotificationReceiver.keyNotificationType,
            NotificationReceiver.keyNotificationId,
        ).forEach(::removeExtra)
    }
}
