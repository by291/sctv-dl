package dev.sctvdl.data.downloads

import android.app.DownloadManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import dev.sctvdl.data.database.SctvDatabase
import dev.sctvdl.data.downloads.DownloadReconciler
import dev.sctvdl.data.downloads.local.RoomDownloadStore
import dev.sctvdl.data.downloads.platform.DownloadManagerGateway
import dev.sctvdl.data.downloads.platform.PlatformDownloadRequest
import dev.sctvdl.data.network.UpstreamUrlPolicy
import dev.sctvdl.domain.download.DownloadState
import dev.sctvdl.domain.download.DownloadTask
import dev.sctvdl.domain.media.Quality
import java.net.ServerSocket
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadStorageTest {
    @Test fun aQueuedJobRetainsItsPlannedIdentityBeforeAnyFileExists() = runBlocking {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun shell(command: String) = automation.executeShellCommand(command).use {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(it).bufferedReader().readText().trim()
        }
        val originalWifi = shell("settings get global wifi_on")
        val context = InstrumentationRegistry.getInstrumentation().context
        val gateway = DownloadManagerGateway(context)
        val filename = "pending-test-${UUID.randomUUID()}.mp4"
        val url = "http://127.0.0.1:9/fixture.mp4"
        var systemId: Long? = null
        try {
            shell("svc wifi disable")
            val connectivity = context.getSystemService(ConnectivityManager::class.java)
            // The preference flips before ConnectivityService has removed the Wi-Fi network.
            withTimeout(10_000) {
                while (shell("settings get global wifi_on") != "0" || connectivity.allNetworks.any {
                        connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ==
                            true
                    }
                ) {
                    delay(50)
                }
            }
            systemId = gateway.enqueue(PlatformDownloadRequest(url, "Disposable waiting fixture", filename, true))
            val manager = context.getSystemService(DownloadManager::class.java)
            manager.query(DownloadManager.Query().setFilterById(systemId)).use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(
                    "Fixture must have no local file",
                    null,
                    cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                )
            }
            val snapshots = gateway.queryOwned()
            val recovered = DownloadReconciler(gateway).resolve(fixture(filename).copy(url = url), snapshots)
            assertEquals(systemId, recovered.systemId)
            assertTrue(recovered.state == DownloadState.Pending || recovered.state == DownloadState.Waiting)
        } finally {
            systemId?.let { gateway.remove(it) }
            shell("svc wifi ${if (originalWifi == "1") "enable" else "disable"}")
        }
    }

    @Test
    fun reservationsAndSystemIdsSurviveDatabaseReopening() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val name = "download-test-${UUID.randomUUID()}.db"
        var database = Room.databaseBuilder(context, SctvDatabase::class.java, name).build()
        try {
            val task = fixture("durable.mp4")
            val store = RoomDownloadStore(database)
            assertTrue(store.reserve(task))
            assertFalse(store.reserve(task.copy(id = "duplicate")))
            store.update(task.copy(systemId = 123, state = DownloadState.Waiting))
            database.close()
            database = Room.databaseBuilder(context, SctvDatabase::class.java, name).build()
            val restored = RoomDownloadStore(database).get(task.id)
            assertEquals(123L, restored?.systemId)
            assertEquals(DownloadState.Waiting, restored?.state)
            assertTrue(restored?.wifiOnly == true)
        } finally {
            database.close()
            context.deleteDatabase(name)
        }
    }

    @Test
    fun platformTransferRestoresCompletedUriAndDetectsExternalRemoval() = runBlocking {
        // This tiny MP4 container header is a transport fixture, not a playable episode.
        val body = byteArrayOf(
            0, 0, 0, 24, 102, 116, 121, 112, 105, 115, 111, 109,
            0, 0, 2, 0, 105, 115, 111, 109, 109, 112, 52, 49
        )
        val referer = AtomicReference<String?>()
        val server = ServerSocket(0)
        val worker = Thread {
            runCatching {
                server.accept().use { socket ->
                    val reader = socket.getInputStream().bufferedReader()
                    var line = reader.readLine()
                    while (!line.isNullOrEmpty()) {
                        if (line.startsWith(
                                "Referer:",
                                true
                            )
                        ) {
                            referer.set(line.substringAfter(':').trim())
                        }
                        line = reader.readLine()
                    }
                    socket.getOutputStream().use { output ->
                        val headers = "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\n" +
                            "Content-Length: ${body.size}\r\nConnection: close\r\n\r\n"
                        output.write(headers.toByteArray())
                        output.write(body)
                    }
                }
            }
        }.apply {
            isDaemon = true
            start()
        }
        val context = InstrumentationRegistry.getInstrumentation().context
        val gateway = DownloadManagerGateway(context)
        val filename = "sctv-test-${UUID.randomUUID()}.mp4"
        var systemId: Long? = null
        try {
            systemId = gateway.enqueue(
                PlatformDownloadRequest(
                    "http://127.0.0.1:${server.localPort}/fixture.mp4",
                    "Disposable test",
                    filename,
                    false
                )
            )
            val snapshot = withTimeout(45_000) {
                withContext(Dispatchers.IO) {
                    var current = gateway.query(listOf(systemId)).single()
                    while (current.state != DownloadState.Completed && current.state != DownloadState.Failed) {
                        delay(200)
                        current = gateway.query(listOf(systemId)).single()
                    }
                    current
                }
            }
            assertEquals(snapshot.reason, DownloadState.Completed, snapshot.state)
            assertEquals(body.size.toLong(), snapshot.bytes)
            assertEquals(UpstreamUrlPolicy.REFERER, referer.get())
            assertNotNull(snapshot.contentUri)
            val reconciler = DownloadReconciler(gateway)
            val restored = reconciler.resolve(
                fixture(filename).copy(systemId = systemId),
                listOf(snapshot)
            )
            assertEquals(DownloadState.Completed, restored.state)
            assertTrue(gateway.isAvailable(requireNotNull(restored.contentUri)))
            gateway.remove(systemId)
            assertEquals(
                DownloadState.Missing,
                reconciler.resolve(
                    restored,
                    gateway.queryOwned()
                ).state
            )
        } finally {
            systemId?.let { gateway.remove(it) }
            server.close()
            worker.join(1_000)
        }
    }

    private fun fixture(filename: String) = DownloadTask(
        "task", "1", "测试节目", "测试栏目", LocalDate.of(2026, 10, 6), Quality.Standard,
        Quality.Standard,
        "https://fscgc.scgchc.com/fixture.mp4",
        filename,
        true,
        createdAt = Instant.EPOCH

    )
}
