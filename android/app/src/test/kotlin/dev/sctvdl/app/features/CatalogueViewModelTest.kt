package dev.sctvdl.app.features

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.app.FakeFavourites
import dev.sctvdl.app.FakeProgrammes
import dev.sctvdl.app.MainDispatcherRule
import dev.sctvdl.app.features.catalogue.CatalogueViewModel
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.CachedResource
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.Programme
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CatalogueViewModelTest {
    @get:Rule val main = MainDispatcherRule()
    private val rows =
        listOf(
            Programme("1", "Zulu", null, 0),
            Programme("2", "Alpha", null, 1),
            Programme("3", "Beta", null, 2)
        )

    @Test fun filtersAndSortKeepFavouritesFirstAndRetainCacheErrors() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val favourites = FakeFavourites().apply { ids.value = setOf("3") }
        val model = CatalogueViewModel(repo, favourites, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()
        assertEquals(listOf("3", "1", "2"), model.state.value.rows(false).map { it.id })
        model.sort(true)
        runCurrent()
        assertEquals(listOf("3", "2", "1"), model.state.value.rows(false).map { it.id })
        repo.catalogue.value = CachedResource(rows, error = AppError(ErrorKind.Network, "offline"))
        runCurrent()
        assertEquals(3, model.state.value.rows(false).size)
        assertEquals(ErrorKind.Network, model.state.value.resource.error?.kind)
    }

    @Test fun searchAndSortRestoreAndEmptyStatesAreDistinct() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val saved = SavedStateHandle(mapOf("query" to "Alpha", "byName" to true))
        val model = CatalogueViewModel(repo, FakeFavourites(), saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()
        assertEquals(listOf("2"), model.state.value.rows(false).map { it.id })
        model.query("不存在")
        runCurrent()
        assertEquals("没有匹配的栏目", model.state.value.emptyReason(false))
        model.query("")
        repo.catalogue.value = CachedResource(emptyList())
        runCurrent()
        assertEquals("暂无栏目", model.state.value.emptyReason(false))
        assertEquals("", saved.get<String>("query"))
    }

    @Test fun restoredFavouriteFilterUsesItsOwnSearchAndSort() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val favourites = FakeFavourites().apply { ids.value = setOf("2", "3") }
        val saved = SavedStateHandle(
            mapOf(
                "query" to "Zulu",
                "byName" to false,
                "favouritesOnly" to true,
                "favouritesQuery" to "Beta",
                "favouritesByName" to true
            )
        )
        val model = CatalogueViewModel(repo, favourites, saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()

        assertEquals("Beta", model.state.value.query)
        assertEquals(true, model.state.value.byName)
        assertEquals(listOf("3"), model.state.value.rows(true).map { it.id })
        model.query("Alpha")
        model.sort(false)
        runCurrent()

        assertEquals("Zulu", saved.get<String>("query"))
        assertEquals("Alpha", saved.get<String>("favouritesQuery"))
        assertEquals(false, saved.get<Boolean>("favouritesByName"))
        model.filter(false)
        runCurrent()
        assertEquals("Zulu", model.state.value.query)
        assertEquals(false, model.state.value.favouritesOnly)
        model.filter(true)
        runCurrent()
        assertEquals("Alpha", model.state.value.query)
        assertEquals(listOf("2"), model.state.value.rows(true).map { it.id })
    }

    @Test fun explorationChoosesFromLoadedProgrammesAndClearsForAnEmptyCatalogue() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val saved = SavedStateHandle()
        val model = CatalogueViewModel(repo, FakeFavourites(), saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()

        assertTrue(saved.get<String>("featuredId") in setOf("1", "2", "3"))
        repo.catalogue.value = CachedResource(emptyList())
        runCurrent()
        assertNull(saved.get<String>("featuredId"))
    }

    @Test fun explorationRetainsItsChoiceOnRefreshAndReplacesARemovedProgramme() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val saved = SavedStateHandle(mapOf("featuredId" to "2"))
        val model = CatalogueViewModel(repo, FakeFavourites(), saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()

        repo.catalogue.value = CachedResource(rows.map { it.copy(name = "Updated ${it.name}") })
        runCurrent()
        assertEquals("2", saved.get<String>("featuredId"))
        repo.catalogue.value = CachedResource(listOf(rows[2]))
        runCurrent()
        assertEquals("3", saved.get<String>("featuredId"))
    }

    @Test fun exploringAnotherExcludesTheCurrentProgrammeAndUsesRefreshedMetadata() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows.take(2)) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle(mapOf("featuredId" to "1")))
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.state.collect() }
        runCurrent()

        model.exploreAnother()
        runCurrent()
        assertEquals("2", model.state.value.featured?.id)
        repo.catalogue.value = CachedResource(listOf(rows[1].copy(name = "Updated programme")))
        runCurrent()
        assertEquals("Updated programme", model.state.value.featured?.name)
        model.exploreAnother()
        runCurrent()
        assertEquals("2", model.state.value.featured?.id)
    }
}
