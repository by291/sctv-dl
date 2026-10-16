package uz.shs.better_player_plus

import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.source.SinglePeriodTimeline
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.trackselection.FixedTrackSelection
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.MediaSource.MediaPeriodId
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@UnstableApi
@RunWith(AndroidJUnit4::class)
class BoundedLoadControlTest {
    @Test
    fun stopsAtByteBudgetEvenBeforeMinimumDurationAndResumesAfterConsumption() {
        // Use the package's previous 109-minute setting: the native byte budget
        // must protect the heap even if a caller requests a long time horizon.
        val control = CustomDefaultLoadControl(25_000, 6_553_600, 3000, 6000).build()
        val playerId = PlayerId.UNSET
        control.onPrepared(playerId)
        val allocator = control.getAllocator(playerId)
        val timeline = SinglePeriodTimeline(600_000_000, true, false, false, null, MediaItem.fromUri("https://fixture.invalid/video.mp4"))
        val parameters = LoadControl.Parameters(
            playerId, timeline, MediaPeriodId(timeline.getUidOfPeriod(0)), 0, 100_000,
            2f, false, false, C.TIME_UNSET, C.TIME_UNSET
        )
        val video = TrackGroup(Format.Builder().setSampleMimeType("video/avc").build())
        val audio = TrackGroup(Format.Builder().setSampleMimeType("audio/mp4a-latm").build())
        control.onTracksSelected(parameters, TrackGroupArray(video, audio), arrayOf(FixedTrackSelection(video, 0), FixedTrackSelection(audio, 0)))
        val allocations = ArrayList<androidx.media3.exoplayer.upstream.Allocation>()
        try {
            assertTrue(control.shouldContinueLoading(parameters))
            while (allocator.totalBytesAllocated < 24 * 1024 * 1024) {
                allocations.add(allocator.allocate())
            }
            assertFalse("24 MiB must stop loading despite the minimum duration", control.shouldContinueLoading(parameters))
            // Playback can begin at the byte limit instead of deadlocking on
            // high-bitrate samples that cannot satisfy the time threshold.
            assertTrue(control.shouldStartPlayback(parameters))
            allocations.forEach { allocator.release(it) }
            allocations.clear()
            assertTrue(control.shouldContinueLoading(parameters))
        } finally {
            allocations.forEach { allocator.release(it) }
            control.onReleased(playerId)
        }
    }
}
