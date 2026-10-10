package dev.sctvdl.domain

import dev.sctvdl.domain.download.safeDownloadFilename
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.VideoVariant
import dev.sctvdl.domain.media.resolveVideo
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.programme.isFullEpisode
import dev.sctvdl.domain.programme.sortProgrammes
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgrammePoliciesTest {
    private val date = LocalDate.of(2026, 10, 6)

    @Test fun smoothUsesTheSmoothFieldAndStandardFallsBack() {
        val content =
            ProgrammeContent(
                "2107420533961056258",
                "新闻",
                standardUrl = "standard.mp4",
                smoothUrl = "smooth.mp4"
            )
        assertEquals(
            VideoVariant(Quality.Smooth, "smooth.mp4"),
            resolveVideo(content, Quality.Smooth)
        )
        assertEquals(
            VideoVariant(Quality.Smooth, "smooth.mp4"),
            resolveVideo(content.copy(standardUrl = null), Quality.Standard)
        )
    }

    @Test fun duplicateSourcesProduceOneVariant() {
        assertEquals(
            listOf(VideoVariant(Quality.Standard, "same.mp4")),
            videoVariants(
                ProgrammeContent("1", "片段", standardUrl = "same.mp4", smoothUrl = "same.mp4")
            )
        )
    }

    @Test fun fullEpisodeRequiresTheExactProgrammeAndDate() {
        assertTrue(isFullEpisode(ProgrammeContent("1", " 四川 新闻联播 （2026.10.06） "), "四川新闻联播", date))
        assertTrue(isFullEpisode(ProgrammeContent("2", "四川新闻联播(2026.10.06)"), "四川新闻联播", date))
        assertFalse(isFullEpisode(ProgrammeContent("3", "今天的第一条新闻"), "四川新闻联播", date))
        assertFalse(isFullEpisode(ProgrammeContent("4", "四川新闻联播（2026.10.05）"), "四川新闻联播", date))
    }

    @Test fun filenamesKeepChineseAndActualQualityButRemoveUnsafeCharacters() {
        assertEquals(
            "2026-10-06_新闻_现场__流畅_abc.mp4",
            safeDownloadFilename(date, "新闻/现场?", Quality.Smooth, "abc")
        )
        val long = safeDownloadFilename(date, "新".repeat(300) + " .", Quality.Standard)
        assertTrue(long.length <= 154)
        assertTrue(long.endsWith("_标清.mp4"))
        assertFalse(long.contains('/'))
    }

    @Test fun favouritesRemainFirstInServiceAndNameOrder() {
        val rows =
            listOf(
                Programme("a", "Zulu", null, 0),
                Programme("b", "Alpha", null, 1),
                Programme("c", "Beta", null, 2)
            )
        assertEquals(listOf("c", "a", "b"), sortProgrammes(rows, setOf("c"), false).map { it.id })
        assertEquals(listOf("c", "b", "a"), sortProgrammes(rows, setOf("c"), true).map { it.id })
    }

    @Test fun unicodeFilenamesFitTheFilesystemByteLimitWithoutSplittingCodePoints() {
        for (title in listOf("新".repeat(300), "📺新闻".repeat(100))) {
            val filename = safeDownloadFilename(date, title, Quality.Standard, "0123456789ab")
            assertTrue(filename.toByteArray(Charsets.UTF_8).size <= 255)
            assertEquals(filename, filename.toByteArray(Charsets.UTF_8).toString(Charsets.UTF_8))
            assertTrue(filename.endsWith("_标清_0123456789ab.mp4"))
        }
    }

    @Test fun emptyCatalogueAndMissingVideoRemainEmpty() {
        assertEquals(emptyList<Programme>(), sortProgrammes(emptyList(), emptySet(), false))
        assertNull(resolveVideo(ProgrammeContent("1", "没有视频"), Quality.Standard))
        assertEquals(emptyList<VideoVariant>(), videoVariants(ProgrammeContent("1", "没有视频")))
    }
}
