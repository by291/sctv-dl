package dev.sctvdl.feature.programmes

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.programme.BroadcastDate
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.programme.ProgrammeContent
import dev.sctvdl.domain.repository.FavouriteRepository
import dev.sctvdl.domain.repository.ProgrammeRepository
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.feature.programmes.archive.ArchiveScreen
import dev.sctvdl.feature.programmes.archive.ArchiveViewModel
import dev.sctvdl.feature.programmes.catalogue.CatalogueScreen
import dev.sctvdl.feature.programmes.catalogue.CatalogueViewModel
import dev.sctvdl.ui.theme.SctvAppTheme
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ContentUpdatesTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
    private val date = BroadcastDate("date", LocalDate.of(2026, 10, 8))

    @Test fun libraryAppliesBackgroundResultsOnlyAfterTheNoticeIsClicked() = checkLibraryUpdate(false)

    @Test fun libraryUpdateActionKeepsContentInPlaceAtLargeText() = checkLibraryUpdate(true)

    private fun checkLibraryUpdate(largeText: Boolean) {
        val repo = UpdateRepository()
        lateinit var model: CatalogueViewModel
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                model = CatalogueViewModel(repo, UpdateFavourites(), SavedStateHandle())
                activity.setContent {
                    val state by model.uiState.collectAsStateWithLifecycle()
                    val density = LocalDensity.current
                    CompositionLocalProvider(LocalDensity provides if (largeText) Density(1f, 2f) else density) {
                        Box(if (largeText) Modifier.requiredSize(320.dp, 700.dp) else Modifier) {
                            SctvAppTheme(AppSettings(theme = if (largeText) ThemeMode.Dark else ThemeMode.Light)) {
                                CatalogueScreen(
                                    state, false, model::query, model::sort, model::refresh,
                                    model::toggleFavourite, {}, model::filter,
                                    onApplyUpdates = model::applyUpdates
                                )
                            }
                        }
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.text("Alpha")), 5_000))
            val explorationBounds = requireNotNull(device.findObject(By.text("栏目探索"))).visibleBounds
            scenario.onActivity {
                repo.programmes.value = CachedResource(listOf(Programme("new", "Beta", null, 0)))
            }
            val notice = device.wait(Until.findObject(By.desc("有新内容，点击更新")), 5_000)
            assertNotNull(notice)
            assertNotNull(device.findObject(By.text("Alpha")))
            assertEquals(
                "Pending updates must not move the visible content",
                explorationBounds,
                requireNotNull(device.findObject(By.text("栏目探索"))).visibleBounds
            )
            assertTrue(
                "The update action belongs in the toolbar",
                notice!!.visibleBounds.bottom <= requireNotNull(device.findObject(By.text("全部栏目"))).visibleBounds.top
            )
            assertNull(device.findObject(By.text("Beta")))
            assertNull(device.findObject(By.clazz("android.widget.ProgressBar")))
            notice.click()
            assertNotNull(device.wait(Until.findObject(By.text("Beta")), 5_000))
            assertTrue(device.wait(Until.gone(By.desc("有新内容，点击更新")), 5_000))
            assertNull(device.findObject(By.text("Alpha")))
        }
    }

    @Test fun archiveSelectionRetainsRowsUntilSelectionEndsAndUpdatesAreAccepted() {
        val repo = UpdateRepository().apply {
            dates.value = CachedResource(listOf(date))
            contents.value = CachedResource(listOf(ProgrammeContent("old", "Accepted clip", standardUrl = "old.mp4")))
        }
        lateinit var model: ArchiveViewModel
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                model = ArchiveViewModel(repo, UpdateFavourites(), SavedStateHandle())
                model.open("one")
                activity.setContent {
                    val state by model.uiState.collectAsStateWithLifecycle()
                    SctvAppTheme(AppSettings()) {
                        ArchiveScreen(
                            state, false, {}, model::selectDate, model::refresh, model::toggleFavourite, {},
                            model::beginSelection, model::selectAll, model::selectFullEpisodes, model::toggleContent,
                            model::exitSelection, {}, onApplyUpdates = model::applyUpdates
                        )
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.text("Accepted clip")), 5_000))
            val clipBounds = requireNotNull(device.findObject(By.text("Accepted clip"))).visibleBounds
            requireNotNull(device.findObject(By.text("批量下载"))).click()
            assertNotNull(device.wait(Until.findObject(By.text("全选")), 5_000))
            scenario.onActivity {
                repo.contents.value = CachedResource(
                    listOf(ProgrammeContent("new", "New clip", standardUrl = "new.mp4"))
                )
            }
            device.waitForIdle()
            assertNull(device.findObject(By.desc("有新内容，点击更新")))
            requireNotNull(device.findObject(By.text("Accepted clip"))).click()
            assertNotNull(device.wait(Until.findObject(By.text("已选 1 个")), 5_000))
            scenario.onActivity { assertEquals(setOf("old"), model.uiState.value.selectedIds) }
            requireNotNull(device.findObject(By.desc("退出选择"))).click()
            val notice = device.wait(Until.findObject(By.desc("有新内容，点击更新")), 5_000)
            assertNotNull(notice)
            assertNotNull(device.findObject(By.text("Accepted clip")))
            assertEquals(
                "Ending selection with a pending update must not move the retained clip",
                clipBounds,
                requireNotNull(device.findObject(By.text("Accepted clip"))).visibleBounds
            )
            notice!!.click()
            assertNotNull(device.wait(Until.findObject(By.text("New clip")), 5_000))
            assertNull(device.findObject(By.text("Accepted clip")))
        }
    }

    @Test fun uncachedArchiveSkeletonsBecomeErrorsOrConfirmedEmptyResults() {
        val repo = UpdateRepository()
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val model = ArchiveViewModel(repo, UpdateFavourites(), SavedStateHandle())
                model.open("one")
                activity.setContent {
                    val state by model.uiState.collectAsStateWithLifecycle()
                    SctvAppTheme(AppSettings()) {
                        Box(Modifier.semantics { testTagsAsResourceId = true }) {
                            ArchiveScreen(
                                state, false, {}, model::selectDate, model::refresh, model::toggleFavourite, {},
                                model::beginSelection, model::selectAll, model::selectFullEpisodes,
                                model::toggleContent,
                                model::exitSelection, {}, onApplyUpdates = model::applyUpdates
                            )
                        }
                    }
                }
            }
            assertNotNull(device.wait(Until.findObject(By.res("archive-dates-placeholder")), 5_000))
            val content = device.wait(Until.findObject(By.res("archive-content-placeholder")), 5_000)
            assertNotNull(content)
            assertTrue(!content!!.isClickable)
            scenario.onActivity {
                repo.dates.value = CachedResource(error = AppError(ErrorKind.Network, "Fixture failure"))
            }
            assertNotNull(device.wait(Until.findObject(By.text("重新连接")), 5_000))
            assertTrue(device.wait(Until.gone(By.res("archive-content-placeholder")), 5_000))
            scenario.onActivity {
                repo.contents.value = CachedResource(emptyList())
                repo.dates.value = CachedResource(listOf(date))
            }
            assertNotNull(device.wait(Until.findObject(By.text("这一天暂无节目")), 5_000))
            assertNull(device.findObject(By.res("archive-dates-placeholder")))
            assertNull(device.findObject(By.res("archive-content-placeholder")))
            assertNull(device.findObject(By.desc("有新内容，点击更新")))
        }
    }
}

private class UpdateRepository : ProgrammeRepository {
    val programmes = MutableStateFlow(CachedResource(listOf(Programme("one", "Alpha", null, 0))))
    val dates = MutableStateFlow(CachedResource<List<BroadcastDate>>())
    val contents = MutableStateFlow(CachedResource<List<ProgrammeContent>>())

    override fun observeProgrammes() = programmes

    override suspend fun refreshProgrammes() {}

    override fun observeDates(programmeId: String) = dates

    override suspend fun refreshDates(programmeId: String) {}

    override fun observeContents(programmeId: String, dateId: String) = contents

    override suspend fun refreshContents(programmeId: String, dateId: String) {}
}

private class UpdateFavourites : FavouriteRepository {
    override fun observeIds() = MutableStateFlow(emptySet<String>())

    override suspend fun toggle(id: String) {}
}
