package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.programme.ProgrammeContent
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

class ClipPublicationLabelTest {
    @Test fun clockOnlyLabelsAreUsedOnlyWhenThePublicationMatchesTheBroadcastDate() {
        val broadcast = LocalDate.of(2026, 10, 9)
        val clip = ProgrammeContent("clip", "News", publishedAt = "2026-10-09 18:40:05")
        assertEquals("18:40:05", clipPublicationLabel(clip, broadcast))
        assertEquals("2026-10-09 18:40:05", clipPublicationLabel(clip, broadcast.minusDays(1)))
        assertEquals("2026-10-09 18:40:05", clipPublicationLabel(clip, null))
        assertEquals("时间未知", clipPublicationLabel(clip.copy(publishedAt = "2026-02-30 18:40:05"), broadcast))
    }
}
