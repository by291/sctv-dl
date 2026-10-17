package dev.sctvdl.domain

import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.history.isViewingCompleted
import dev.sctvdl.domain.history.resumePositionMs
import java.time.Instant
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ViewingPolicyTest {
    @Test fun completionRequiresKnownPositiveDurationOrEnd() {
        assertFalse(isViewingCompleted(100, null, false))
        assertFalse(isViewingCompleted(100, 0, false))
        assertFalse(isViewingCompleted(949, 1000, false))
        assertTrue(isViewingCompleted(950, 1000, false))
        assertTrue(isViewingCompleted(0, null, true))
    }

    @Test fun completedEntriesReplayAndIncompleteEntriesResume() {
        val target = ViewingTarget.LegacyDownload("1", "Episode", "Programme", LocalDate.of(2026, 10, 17))
        val entry = ViewingEntry(target, 12_000, 100_000, Instant.EPOCH, false)
        assertEquals(12_000, resumePositionMs(entry))
        assertEquals(0, resumePositionMs(entry.copy(completed = true)))
        assertEquals(0, resumePositionMs(null))
    }
}
