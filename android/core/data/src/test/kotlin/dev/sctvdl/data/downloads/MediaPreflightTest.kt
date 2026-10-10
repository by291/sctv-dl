package dev.sctvdl.data.downloads

import dev.sctvdl.data.downloads.preflight.MediaPreflight
import dev.sctvdl.data.downloads.preflight.ProbeResponse
import dev.sctvdl.domain.common.AppException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MediaPreflightTest {
    private val url = "https://fscgc.scgchc.com/NewsMedia/fixture.mp4"

    @Test fun successfulHeadReturnsActualLengthWithoutRange() = runTest {
        val methods = mutableListOf<String>()
        val check =
            MediaPreflight { _, method, range ->
                methods.add(method)
                assertNull(range)
                ProbeResponse(200, "video/mp4", 4096)
            }
        assertEquals(4096L, check.check(url))
        assertEquals(listOf("HEAD"), methods)
    }

    @Test fun unsupportedHeadUsesABoundedRangeAndUnknownLengthStaysUnknown() = runTest {
        val methods = mutableListOf<String>()
        val check = MediaPreflight { _, method, range ->
            methods.add(method)
            if (method ==
                "HEAD"
            ) {
                ProbeResponse(405, null)
            } else {
                assertEquals("bytes=0-0", range)
                ProbeResponse(206, "video/mp4", 1, 8192)
            }
        }
        assertEquals(8192L, check.check(url))
        assertEquals(listOf("HEAD", "GET"), methods)
        assertNull(
            MediaPreflight { _, _, _ ->
                ProbeResponse(200, "application/octet-stream")
            }.check(url)
        )
    }

    @Test fun unsafeOriginsRedirectsAndHtmlAreRejected() = runTest {
        var calls = 0
        val check = MediaPreflight { _, _, _ ->
            calls++
            ProbeResponse(200, "text/html")
        }
        assertTrue(
            runCatching {
                check.check("https://evil.test/a.mp4")
            }.exceptionOrNull() is AppException
        )
        assertEquals(0, calls)
        assertTrue(runCatching { check.check(url) }.exceptionOrNull() is AppException)
        assertTrue(
            runCatching {
                MediaPreflight { _, _, _ -> ProbeResponse(302, "video/mp4") }.check(url)
            }.exceptionOrNull() is AppException
        )
    }
}
