package dev.sctvdl.flutter

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.bbflight.background_downloader.NotificationReceiver
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NotificationLaunchIntentTest {
    @Test fun matchingAcknowledgementClearsOnlyPluginLaunchData() {
        val intent = Intent(NotificationReceiver.actionTap)
            .putExtra(NotificationReceiver.keyTask, "{\"taskId\":\"attempt-1\"}")
            .putExtra(NotificationReceiver.keyNotificationId, 11)
            .putExtra("unrelated", "retained")
        val cleaned = consumeDownloadNotificationIntent(intent, "attempt-1")!!
        assertEquals(Intent.ACTION_MAIN, cleaned.action)
        assertFalse(cleaned.hasExtra(NotificationReceiver.keyTask))
        assertFalse(cleaned.hasExtra(NotificationReceiver.keyNotificationId))
        assertEquals("retained", cleaned.getStringExtra("unrelated"))
        assertEquals(NotificationReceiver.actionTap, intent.action)
    }

    @Test fun acknowledgementCannotConsumeAnotherTasksNewerIntent() {
        val newer = Intent(NotificationReceiver.actionTap)
            .putExtra(NotificationReceiver.keyTask, "{\"taskId\":\"attempt-2\"}")
        assertNull(consumeDownloadNotificationIntent(newer, "attempt-1"))
        assertNull(consumeDownloadNotificationIntent(newer, null))
        assertTrue(newer.hasExtra(NotificationReceiver.keyTask))
    }
}
