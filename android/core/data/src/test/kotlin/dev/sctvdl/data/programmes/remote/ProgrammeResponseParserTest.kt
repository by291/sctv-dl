package dev.sctvdl.data.programmes.remote

import dev.sctvdl.data.programmes.remote.ProgrammeResponseParser
import dev.sctvdl.domain.common.AppException
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.media.Quality
import dev.sctvdl.domain.media.resolveVideo
import dev.sctvdl.domain.media.videoVariants
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgrammeResponseParserTest {
    private val parser = ProgrammeResponseParser()

    @Test fun stringIdsRemainExactAndSafeNumbersNormalize() {
        val rows = parser.programmes(
            """{"rs":200,"data":{"records":[{"id":"2107420533961056258","name":"四川"},{"id":42,"name":"新闻"}]}}"""
        )
        assertEquals(listOf("2107420533961056258", "42"), rows.map { it.id })
    }

    @Test fun unsafeNumericIdsAndInvalidDatesFailValidation() {
        expect(ErrorKind.InvalidData) {
            parser.programmes("""{"rs":200,"data":{"records":[{"id":9007199254740992}]}}""")
        }
        expect(ErrorKind.InvalidData) {
            parser.dates("""{"rs":200,"data":[{"id":"1","date":"2026-02-30"}]}""")
        }
        expect(ErrorKind.InvalidData) {
            parser.dates("""{"rs":200,"data":[{"id":"1","date":"2026-2-3"}]}""")
        }
    }

    @Test fun duplicateDatesKeepTheLastRecordAndSortNewestFirst() {
        val rows = parser.dates(
            """{"rs":200,"data":[{"id":"1","date":"2026-10-05"},{"id":"2","date":"2026-10-06"},{"id":"3","date":"2026-10-05"}]}"""
        )
        assertEquals(listOf("2", "3"), rows.map { it.id })
    }

    @Test fun omittedMediaIsNullAndTheSmoothFieldIsMappedExplicitly() {
        val rows = parser.contents(
            """{"rs":200,"data":[{"id":"1","title":"文本"},{"id":"2","video":"NewsMedia/a.mp4","videoStandard":"standard/b.mp4"}]}"""
        )
        assertNull(rows[0].standardUrl)
        assertNull(rows[0].coverUrl)
        assertEquals("https://fscgc.scgchc.com/standard/b.mp4", rows[1].smoothUrl)
        assertEquals(Quality.Smooth, resolveVideo(rows[1], Quality.Smooth)?.quality)
    }

    @Test fun businessAndMalformedResponsesHaveDistinctErrors() {
        expect(ErrorKind.Business) { parser.dates("""{"rs":500,"error":"维护中","data":[]}""") }
        expect(ErrorKind.InvalidData) { parser.contents("<html>not json</html>") }
        expect(ErrorKind.InvalidData) { parser.programmes("""{"rs":200,"data":[]}""") }
    }

    @Test fun duplicateVideoUrlsExposeOneChoice() {
        val row = parser.contents(
            """{"rs":200,"data":[{"id":"1","video":"a.mp4","videoStandard":"a.mp4"}]}"""
        ).single()
        assertEquals(1, videoVariants(row).size)
    }

    private fun expect(kind: ErrorKind, action: () -> Unit) {
        val error = runCatching(action).exceptionOrNull()
        assertTrue("Expected a typed upstream error", error is AppException)
        assertEquals(kind, (error as AppException).error.kind)
    }
}
