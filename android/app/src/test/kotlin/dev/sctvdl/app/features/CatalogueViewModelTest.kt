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
}
