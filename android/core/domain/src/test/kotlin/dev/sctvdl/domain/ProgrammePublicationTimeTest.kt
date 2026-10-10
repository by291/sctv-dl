package dev.sctvdl.domain

import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.publicationTime
import dev.sctvdl.domain.programme.sortContentsByPublicationTime
import java.time.LocalDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProgrammePublicationTimeTest {
    @Test fun publicationTextUsesTheUpstreamCalendarWithoutDeviceTimezoneConversion() {
        val content = ProgrammeContent("clip", "News", publishedAt = " 2026-10-09 18:40:05 ")
        assertEquals(LocalDateTime.of(2026, 10, 9, 18, 40, 5), content.publicationTime())
    }

    @Test fun invalidCalendarValuesAndMissingTimesRemainUnknown() {
        for (value in listOf(null, "", " ", "18:40:05", "unknown", "2026-02-30 18:40:05", "2026-10-09 24:01:00")) {
            assertNull(value, ProgrammeContent("clip", "News", publishedAt = value).publicationTime())
        }
    }

    @Test fun orderingUsesTheWholeTimestampAcrossMidnightAndYearBoundaries() {
        val rows = listOf(
            ProgrammeContent("new-year", "New year", publishedAt = "2027-01-01 00:00:01"),
            ProgrammeContent("old-year", "Old year", publishedAt = "2026-12-31 23:59:59"),
            ProgrammeContent("midnight", "Midnight", publishedAt = "2027-01-01 00:00:00")
        )
        assertEquals(listOf("old-year", "midnight", "new-year"), sortContentsByPublicationTime(rows).map { it.id })
        assertEquals(
            listOf("new-year", "midnight", "old-year"),
            sortContentsByPublicationTime(rows, ascending = false).map { it.id }
        )
        assertEquals(listOf("new-year", "old-year", "midnight"), rows.map { it.id })
    }
}
