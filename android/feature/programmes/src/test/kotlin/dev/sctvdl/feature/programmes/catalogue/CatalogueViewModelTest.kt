package dev.sctvdl.feature.programmes.catalogue

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.repository.FavouriteRepository
import dev.sctvdl.domain.testing.FakeFavourites
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.domain.testing.MainDispatcherRule
import dev.sctvdl.feature.programmes.catalogue.CatalogueViewModel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    @Test fun backgroundResultsDoNotReplaceTheVisibleCatalogue() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle(mapOf("featuredId" to "2")))
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        repo.catalogue.value = CachedResource(listOf(Programme("4", "New programme", null, 0)))
        runCurrent()

        assertEquals(listOf("1", "2", "3"), model.uiState.value.rows(false).map { it.id })
        assertEquals("Alpha", model.uiState.value.featured?.name)
        assertTrue(model.uiState.value.hasUpdate)
        model.applyUpdates()
        runCurrent()
        assertEquals(listOf("4"), model.uiState.value.rows(false).map { it.id })
        assertFalse(model.uiState.value.hasUpdate)
    }

    @Test fun entryRefreshesWithoutAcceptingPendingResultsOrLosingFilters() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertEquals(0, repo.catalogueRequests)
        model.enter()
        runCurrent()
        model.query("Updated")
        model.sort(true)
        repo.catalogue.value = CachedResource(listOf(Programme("4", "Updated programme", null, 0)))
        runCurrent()
        model.enter()
        runCurrent()

        assertEquals(2, repo.catalogueRequests)
        assertEquals("Updated", model.uiState.value.query)
        assertEquals(true, model.uiState.value.byName)
        assertEquals(listOf("1", "2", "3"), model.uiState.value.resource.data?.map { it.id })
        assertTrue(model.uiState.value.hasUpdate)
    }

    @Test fun repeatedEntryDoesNotOverlapAnActiveCatalogueRequest() = runTest {
        val gate = CompletableDeferred<Unit>()
        val repo = FakeProgrammes().apply { catalogueRefreshGate = gate }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle())
        model.enter()
        runCurrent()
        model.query("Alpha")
        model.sort(true)
        model.enter()
        model.refresh()
        runCurrent()
        assertEquals(1, repo.catalogueRequests)
        gate.complete(Unit)
        runCurrent()
        model.enter()
        runCurrent()
        assertEquals(2, repo.catalogueRequests)
    }

    @Test fun unchangedResultsAndFailuresDoNotAdvertiseNewContent() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(emptyList()) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        repo.catalogue.value = CachedResource(emptyList(), updatedAt = java.time.Instant.ofEpochSecond(1))
        runCurrent()
        assertFalse(model.uiState.value.hasUpdate)
        repo.catalogue.value = CachedResource(emptyList(), error = AppError(ErrorKind.Network, "offline"))
        runCurrent()
        assertFalse(model.uiState.value.hasUpdate)
        assertEquals(ErrorKind.Network, model.uiState.value.resource.error?.kind)
        repo.catalogue.value = CachedResource(rows)
        runCurrent()
        assertTrue(model.uiState.value.hasUpdate)
        assertTrue(model.uiState.value.resource.data!!.isEmpty())
        repo.catalogue.value = CachedResource(emptyList())
        runCurrent()
        assertFalse(model.uiState.value.hasUpdate)
    }

    @Test fun favouriteChangesKeepTheCurrentServiceOrderAndUpdateTheFavouriteTab() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val favourites = FakeFavourites().apply { ids.value = setOf("3") }
        val model = CatalogueViewModel(repo, favourites, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertEquals(listOf("3", "1", "2"), model.uiState.value.rows(false).map { it.id })

        model.toggleFavourite("3")
        runCurrent()
        assertTrue(model.uiState.value.favourites.isEmpty())
        assertEquals(listOf("3", "1", "2"), model.uiState.value.rows(false).map { it.id })
        assertTrue(model.uiState.value.rows(true).isEmpty())

        model.toggleFavourite("2")
        runCurrent()
        assertEquals(setOf("2"), model.uiState.value.favourites)
        assertEquals(listOf("3", "1", "2"), model.uiState.value.rows(false).map { it.id })
        assertEquals(listOf("2"), model.uiState.value.rows(true).map { it.id })
    }

    @Test fun favouritingAndUnfavouritingKeepNameOrderAndTheSelectedSortMode() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        model.sort(true)
        runCurrent()

        model.toggleFavourite("1")
        runCurrent()
        assertEquals(setOf("1"), model.uiState.value.favourites)
        assertEquals(listOf("2", "3", "1"), model.uiState.value.rows(false).map { it.id })
        assertTrue(model.uiState.value.byName)

        model.toggleFavourite("1")
        runCurrent()
        assertEquals(listOf("2", "3", "1"), model.uiState.value.rows(false).map { it.id })
        assertTrue(model.uiState.value.byName)
    }

    @Test fun reentryKeepsStartupFavouritePriorityAfterUiObservationStops() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val favourites = FakeFavourites().apply { ids.value = setOf("3") }
        val model = CatalogueViewModel(repo, favourites, SavedStateHandle(mapOf("byName" to true)))
        val observer = backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        model.toggleFavourite("3")
        model.toggleFavourite("2")
        runCurrent()
        assertEquals(listOf("3", "2", "1"), model.uiState.value.rows(false).map { it.id })
        observer.cancel()
        advanceTimeBy(5_001)
        runCurrent()
        favourites.ids.value = setOf("1")
        runCurrent()

        model.enter()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertEquals(setOf("1"), model.uiState.value.favourites)
        assertEquals(listOf("3", "2", "1"), model.uiState.value.rows(false).map { it.id })
        assertTrue(model.uiState.value.byName)
    }

    @Test fun refreshKeepsStartupFavouritePriorityWithoutAcceptingPendingCatalogue() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        model.toggleFavourite("3")
        repo.catalogue.value = CachedResource(rows.map { it.copy(name = "Updated ${it.name}") })
        runCurrent()
        assertEquals(listOf("1", "2", "3"), model.uiState.value.rows(false).map { it.id })

        model.refresh()
        runCurrent()
        assertEquals(listOf("1", "2", "3"), model.uiState.value.rows(false).map { it.id })
        assertEquals("Zulu", model.uiState.value.rows(false).first().name)
        assertTrue(model.uiState.value.hasUpdate)
    }

    @Test fun acceptingCatalogueUpdatesKeepsStartupFavouritePriority() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        model.toggleFavourite("3")
        repo.catalogue.value = CachedResource(rows + Programme("4", "New programme", null, 3))
        runCurrent()

        model.applyUpdates()
        runCurrent()
        assertEquals(listOf("1", "2", "3", "4"), model.uiState.value.rows(false).map { it.id })
        assertFalse(model.uiState.value.hasUpdate)
    }

    @Test fun aNewLibrarySessionUsesLatestFavouritePriority() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val favourites = FakeFavourites().apply { ids.value = setOf("3") }
        val current = CatalogueViewModel(repo, favourites, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { current.uiState.collect() }
        runCurrent()

        current.toggleFavourite("3")
        current.toggleFavourite("2")
        runCurrent()
        assertEquals(setOf("2"), current.uiState.value.favourites)
        assertEquals(listOf("3", "1", "2"), current.uiState.value.rows(false).map { it.id })

        val restarted = CatalogueViewModel(repo, favourites, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { restarted.uiState.collect() }
        runCurrent()
        assertEquals(listOf("2", "1", "3"), restarted.uiState.value.rows(false).map { it.id })
        assertEquals(listOf("3", "1", "2"), current.uiState.value.rows(false).map { it.id })
    }

    @Test fun initialFavouritePriorityWaitsForTheFirstRepositoryEmission() = runTest {
        val gate = CompletableDeferred<Unit>()
        val favourites = object : FavouriteRepository {
            override fun observeIds() = flow {
                gate.await()
                emit(setOf("3"))
                awaitCancellation()
            }

            override suspend fun toggle(id: String) = Unit
        }
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val model = CatalogueViewModel(repo, favourites, SavedStateHandle())
        model.enter()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertNull(model.uiState.value.resource.data)

        gate.complete(Unit)
        runCurrent()
        assertEquals(listOf("3", "1", "2"), model.uiState.value.rows(false).map { it.id })
    }

    @Test fun filtersAndSortKeepFavouritesFirstAndRetainCacheErrors() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val favourites = FakeFavourites().apply { ids.value = setOf("3") }
        val model = CatalogueViewModel(repo, favourites, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertEquals(listOf("3", "1", "2"), model.uiState.value.rows(false).map { it.id })
        model.sort(true)
        runCurrent()
        assertEquals(listOf("3", "2", "1"), model.uiState.value.rows(false).map { it.id })
        repo.catalogue.value = CachedResource(rows, error = AppError(ErrorKind.Network, "offline"))
        runCurrent()
        assertEquals(3, model.uiState.value.rows(false).size)
        assertEquals(ErrorKind.Network, model.uiState.value.resource.error?.kind)
    }

    @Test fun searchAndSortRestoreAndEmptyStatesAreDistinct() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val saved = SavedStateHandle(mapOf("query" to "Alpha", "byName" to true))
        val model = CatalogueViewModel(repo, FakeFavourites(), saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()
        assertEquals(listOf("2"), model.uiState.value.rows(false).map { it.id })
        model.query("不存在")
        runCurrent()
        assertEquals("没有匹配的栏目", model.uiState.value.emptyReason(false))
        model.query("")
        repo.catalogue.value = CachedResource(emptyList())
        runCurrent()
        assertEquals("暂无栏目", model.uiState.value.emptyReason(false))
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
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        assertEquals("Beta", model.uiState.value.query)
        assertEquals(true, model.uiState.value.byName)
        assertEquals(listOf("3"), model.uiState.value.rows(true).map { it.id })
        model.query("Alpha")
        model.sort(false)
        runCurrent()

        assertEquals("Zulu", saved.get<String>("query"))
        assertEquals("Alpha", saved.get<String>("favouritesQuery"))
        assertEquals(false, saved.get<Boolean>("favouritesByName"))
        model.filter(false)
        runCurrent()
        assertEquals("Zulu", model.uiState.value.query)
        assertEquals(false, model.uiState.value.favouritesOnly)
        model.filter(true)
        runCurrent()
        assertEquals("Alpha", model.uiState.value.query)
        assertEquals(listOf("2"), model.uiState.value.rows(true).map { it.id })
    }

    @Test fun explorationChoosesFromLoadedProgrammesAndClearsForAnEmptyCatalogue() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val saved = SavedStateHandle()
        val model = CatalogueViewModel(repo, FakeFavourites(), saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        assertTrue(saved.get<String>("featuredId") in setOf("1", "2", "3"))
        repo.catalogue.value = CachedResource(emptyList())
        runCurrent()
        model.applyUpdates()
        runCurrent()
        assertNull(saved.get<String>("featuredId"))
    }

    @Test fun explorationRetainsItsChoiceOnRefreshAndReplacesARemovedProgramme() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows) }
        val saved = SavedStateHandle(mapOf("featuredId" to "2"))
        val model = CatalogueViewModel(repo, FakeFavourites(), saved)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        repo.catalogue.value = CachedResource(rows.map { it.copy(name = "Updated ${it.name}") })
        runCurrent()
        model.applyUpdates()
        runCurrent()
        assertEquals("2", saved.get<String>("featuredId"))
        repo.catalogue.value = CachedResource(listOf(rows[2]))
        runCurrent()
        model.applyUpdates()
        runCurrent()
        assertEquals("3", saved.get<String>("featuredId"))
    }

    @Test fun exploringAnotherExcludesTheCurrentProgrammeAndUsesRefreshedMetadata() = runTest {
        val repo = FakeProgrammes().apply { catalogue.value = CachedResource(rows.take(2)) }
        val model = CatalogueViewModel(repo, FakeFavourites(), SavedStateHandle(mapOf("featuredId" to "1")))
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        model.exploreAnother()
        runCurrent()
        assertEquals("2", model.uiState.value.featured?.id)
        repo.catalogue.value = CachedResource(listOf(rows[1].copy(name = "Updated programme")))
        runCurrent()
        model.applyUpdates()
        runCurrent()
        assertEquals("Updated programme", model.uiState.value.featured?.name)
        model.exploreAnother()
        runCurrent()
        assertEquals("2", model.uiState.value.featured?.id)
    }
}
