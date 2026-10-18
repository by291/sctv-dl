package dev.sctvdl.feature.programmes.catalogue

import androidx.lifecycle.SavedStateHandle
import dev.sctvdl.domain.repository.FavouriteRepository
import dev.sctvdl.domain.testing.FakeProgrammes
import dev.sctvdl.domain.testing.MainDispatcherRule
import java.io.IOException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FavouriteFailureTest {
    @get:Rule val main = MainDispatcherRule()

    @Test fun failedToggleRetainsMembershipAndDoesNotStopLaterActions() = runTest {
        val ids = MutableStateFlow(setOf("1"))
        var fail = true
        val repository = object : FavouriteRepository {
            override fun observeIds() = ids

            override suspend fun toggle(id: String) {
                if (fail) throw IOException("Storage unavailable")
                ids.value = if (id in ids.value) ids.value - id else ids.value + id
            }
        }
        val model = CatalogueViewModel(FakeProgrammes(), repository, SavedStateHandle())
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.uiState.collect() }
        runCurrent()

        model.toggleFavourite("1")
        runCurrent()
        assertEquals(setOf("1"), model.uiState.value.favourites)

        assertNotNull(model.uiState.value.favouriteError)

        fail = false
        model.retryFavourites()
        model.retryFavourites()
        runCurrent()
        assertEquals(emptySet<String>(), model.uiState.value.favourites)
        assertNull(model.uiState.value.favouriteError)
    }
}
