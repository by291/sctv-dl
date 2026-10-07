package dev.sctvdl.app.features.player

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.AppError
import dev.sctvdl.domain.ErrorKind
import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.ProgrammeRepository
import dev.sctvdl.domain.Quality
import dev.sctvdl.domain.SettingsRepository
import dev.sctvdl.domain.videoVariants
import dev.sctvdl.player.PlaybackSource
import java.time.LocalDate
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

data class PlayerUiState(
    val loading: Boolean = true,
    val source: PlaybackSource? = null,
    val content: ProgrammeContent? = null,
    val error: AppError? = null,
    val initialQuality: Quality = Quality.Standard,
    val programmeName: String = "节目",
    val broadcastDate: LocalDate? = null
)

@HiltViewModel
class PlayerViewModel @Inject constructor(
    private val repository: ProgrammeRepository,
    private val settings: SettingsRepository,
    private val saved: SavedStateHandle
) : ViewModel() {
    private val mutableState = MutableStateFlow(PlayerUiState())
    val state = mutableState.asStateFlow()
    private var job: Job? = null
    private var key: Triple<String, String, String>? = null

    fun open(programmeId: String, dateId: String, contentId: String) {
        val currentKey = Triple(programmeId, dateId, contentId)
        if (key == currentKey) return
        key = currentKey
        job?.cancel()
        mutableState.value = PlayerUiState()
        job = viewModelScope.launch {
            launch { repository.refreshContents(programmeId, dateId) }
            combine(
                repository.observeContents(programmeId, dateId),
                settings.settings,
                repository.observeProgrammes(),
                repository.observeDates(programmeId)
            ) {
                    resource,
                    preferences,
                    programmes,
                    dates
                ->
                val content = resource.data?.firstOrNull { it.id == contentId }
                val variants = content?.let(::videoVariants).orEmpty()
                val source = content?.takeIf { variants.isNotEmpty() }?.let {
                    PlaybackSource(
                        it.id,
                        it.title,
                        variants,
                        startPositionMs =
                        saved["positionMs"] ?: 0L
                    )
                }
                val error = if (resource.data != null &&
                    source == null
                ) {
                    AppError(ErrorKind.NoVideo, "该节目暂时无法播放")
                } else {
                    resource.error
                }
                PlayerUiState(
                    resource.data == null && resource.error == null,
                    source,
                    content,
                    error,
                    preferences.initialQuality,
                    programmes.data?.firstOrNull {
                        it.id == programmeId
                    }?.name ?: "节目",
                    dates.data?.firstOrNull {
                        it.id == dateId
                    }?.date
                )
            }.collect { if (key == currentKey) mutableState.value = it }
        }
    }

    fun retry() {
        key?.let { (programmeId, dateId, _) ->
            viewModelScope.launch { repository.refreshContents(programmeId, dateId) }
        }
    }
    fun savePosition(positionMs: Long) {
        saved["positionMs"] = positionMs.coerceAtLeast(0)
    }
}
