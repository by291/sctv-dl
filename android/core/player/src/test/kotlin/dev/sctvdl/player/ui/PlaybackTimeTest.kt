package dev.sctvdl.player.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackTimeTest {
    @Test fun timesPreserveUnknownDurationAndCrossTheHourBoundary() {
        assertEquals("--:--", playbackTime(null))
        assertEquals("59:59", playbackTime(3_599_000))
        assertEquals("1:00:00", playbackTime(3_600_000))
        assertEquals("0:00", playbackTime(-1))
    }
}
