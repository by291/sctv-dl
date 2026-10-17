package dev.sctvdl.feature.programmes.history

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.history.ViewingEntry
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.testing.FakeHistory
import dev.sctvdl.domain.testing.MainDispatcherRule
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class HistoryViewModelTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun restoresSearchAndRemovesOnlyTheSelectedEntry() = runTest {
        val repo = FakeHistory()
        val entry =
            ViewingEntry(
                ViewingTarget.LegacyDownload("7", "Full title", "Programme", LocalDate.of(2026, 10, 17)),
                12_000,
                100_000,
                Instant.EPOCH,
                false
            )
        repo.entries.value = listOf(entry)
        val model = HistoryViewModel(repo, SavedStateHandle(mapOf("historyQuery" to "full")))
        runCurrent()
        assertEquals(listOf(entry), model.state.value.entries)
        model.query("absent")
        runCurrent()
        assertTrue(model.state.value.entries.isEmpty())
        model.query("")
        model.remove(entry.key)
        runCurrent()
        assertTrue(repo.entries.value.isEmpty())
    }
}
