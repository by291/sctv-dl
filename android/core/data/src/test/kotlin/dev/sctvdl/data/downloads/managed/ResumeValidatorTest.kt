package dev.sctvdl.data.downloads.managed

import dev.sctvdl.data.downloads.preflight.MediaIdentity
import java.io.IOException
import org.junit.Assert.assertThrows
import org.junit.Test

class ResumeValidatorTest {
    private val identity = MediaIdentity(1_000, "\"version1\"", null, acceptsRanges = true)

    @Test fun continuationRequiresSameObjectAndExactRange() {
        ResumeValidator.validate(identity, 500, MediaResponse(206, "bytes 500-999/1000", etag = "\"version1\""))
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity, 500, MediaResponse(200, etag = "\"version1\""))
        }
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity, 500, MediaResponse(206, "bytes 500-999/1000", etag = "\"version2\""))
        }
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity, 500, MediaResponse(206, "bytes 500-599/600", etag = "\"version1\""))
        }
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity.copy(etag = null), 500, MediaResponse(206, "bytes 500-999/1000"))
        }
    }
}
