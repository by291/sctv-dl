package dev.sctvdl.data.downloads.managed

import dev.sctvdl.data.downloads.preflight.MediaIdentity
import java.io.IOException
import org.junit.Assert.assertThrows
import org.junit.Test

class ResumeValidatorTest {
    private val identity = MediaIdentity(1000, "\"version1\"", null, true)

    @Test fun continuationRequiresSameObjectAndExactRange() {
        ResumeValidator.validate(identity, 500, 206, "bytes 500-999/1000", "\"version1\"", null)
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity, 500, 200, null, "\"version1\"", null)
        }
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity, 500, 206, "bytes 500-999/1000", "\"version2\"", null)
        }
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity, 500, 206, "bytes 500-599/600", "\"version1\"", null)
        }
        assertThrows(IOException::class.java) {
            ResumeValidator.validate(identity.copy(etag = null), 500, 206, "bytes 500-999/1000", null, null)
        }
    }
}
