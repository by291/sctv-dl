package dev.sctvdl.data

import dev.sctvdl.data.network.UrlPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UrlPolicyTest {
    @Test fun relativeUrlsResolveOnlyToApprovedOrigins() {
        assertEquals(
            "https://fscgc.scgchc.com/NewsMedia/a.mp4",
            UrlPolicy.media("/NewsMedia/a.mp4")
        )
        assertEquals("https://kscgc.sctv.com/a.jpg", UrlPolicy.cover("a.jpg"))
        assertEquals(
            "https://kscgc.scgchc.com/a.jpg",
            UrlPolicy.cover("https://kscgc.scgchc.com/a.jpg")
        )
    }

    @Test fun unsafeTargetsAreNotPlayable() {
        listOf(
            "http://fscgc.scgchc.com/a.mp4",
            "https://evil.test/a.mp4",
            "https://user:pass@fscgc.scgchc.com/a.mp4",
            "https://fscgc.scgchc.com:8443/a.mp4",
            "https://fscgc.scgchc.com/a.m3u8"
        ).forEach {
            assertNull(UrlPolicy.media(it))
        }
        assertNull(UrlPolicy.cover("https://evil.test/a.jpg"))
    }
}
