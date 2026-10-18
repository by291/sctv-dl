package dev.sctvdl.feature.programmes.presentation

import dev.sctvdl.domain.repository.FavouriteRepository
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FavouriteStateTest {
    @Test fun failedObservationRetainsMembershipAndRetryRestartsIt() = runTest {
        val values = MutableStateFlow(setOf("1"))
        var fail = true
        val repository = object : FavouriteRepository {
            override fun observeIds() = flow {
                emit(values.value)
                if (fail) throw IOException("Read failed")
                emitAll(values)
            }

            override suspend fun toggle(id: String) = Unit
        }
        val state = FavouriteState(repository, backgroundScope)
        runCurrent()

        assertEquals(setOf("1"), state.ids.value)
        assertNotNull(state.error.value)

        fail = false
        values.value = setOf("2")
        state.retry()
        runCurrent()

        assertEquals(setOf("2"), state.ids.value)
        assertNull(state.error.value)
    }

    @Test fun initialReadFailureAllowsCatalogueRenderingAndCanRecover() = runTest {
        var fail = true
        val repository = object : FavouriteRepository {
            override fun observeIds() = flow {
                if (fail) throw IOException("Read failed")
                emit(setOf("1"))
            }

            override suspend fun toggle(id: String) = Unit
        }
        val state = FavouriteState(repository, backgroundScope)
        runCurrent()

        assertEquals(emptySet<String>(), state.ids.value)
        assertNotNull(state.error.value)

        fail = false
        state.retry()
        runCurrent()

        assertEquals(setOf("1"), state.ids.value)
        assertNull(state.error.value)
    }

    @Test fun cancelledToggleDoesNotBecomeARetryableStorageFailure() = runTest {
        val repository = object : FavouriteRepository {
            override fun observeIds() = MutableStateFlow(setOf("1"))

            override suspend fun toggle(id: String): Unit = throw CancellationException("Destination left")
        }
        val state = FavouriteState(repository, backgroundScope)
        runCurrent()

        state.toggle("1")
        runCurrent()

        assertEquals(setOf("1"), state.ids.value)
        assertNull(state.error.value)
    }
}
