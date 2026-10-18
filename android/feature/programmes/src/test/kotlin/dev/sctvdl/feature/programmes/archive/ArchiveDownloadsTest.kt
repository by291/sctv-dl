package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.ProgrammeSelection
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArchiveDownloadsTest {
    @Test fun confirmationUsesAcceptedMetadataAndIgnoresMissingOrUnplayableSelections() {
        val programme = Programme("1", "Accepted", "accepted.jpg", 0)
        val date = BroadcastDate("2", LocalDate.of(2026, 10, 18))
        val content = ProgrammeContent("3", "Accepted clip", standardUrl = "https://fscgc.scgchc.com/clip.mp4")
        val state = ArchiveUiState(
            programmeId = programme.id,
            programme = programme,
            date = date,
            contents = CachedResource(listOf(content, ProgrammeContent("4", "Text only"))),
            hasUpdate = true
        )

        val requests = archiveDownloadRequests(state, setOf("3", "4", "missing"), Quality.Smooth, wifiOnly = true)

        assertEquals(1, requests.size)
        assertEquals(ProgrammeSelection(programme, date, content), requests.single().selection)
        assertEquals(Quality.Smooth, requests.single().requestedQuality)
        assertTrue(requests.single().wifiOnly)
    }

    @Test fun confirmationWithoutAnAcceptedBroadcastDoesNotInventADate() {
        val requests = archiveDownloadRequests(ArchiveUiState(), setOf("3"), Quality.Standard, wifiOnly = false)

        assertTrue(requests.isEmpty())
    }
}
