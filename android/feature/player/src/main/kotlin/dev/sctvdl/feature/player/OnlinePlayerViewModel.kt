package dev.sctvdl.feature.player

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.sctvdl.domain.common.AppError
import dev.sctvdl.domain.common.ErrorKind
import dev.sctvdl.domain.history.ViewingTarget
import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.ProgrammeSelection
import dev.sctvdl.domain.repository.HistoryRepository
import dev.sctvdl.domain.repository.ProgrammeRepository
import dev.sctvdl.domain.repository.SettingsRepository
import dev.sctvdl.player.model.PlaybackSource
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

@HiltViewModel
internal class OnlinePlayerViewModel @Inject constructor(
    private val repository: ProgrammeRepository,
    private val settings: SettingsRepository,
    private val saved: SavedStateHandle,
    private val history: HistoryRepository
) : ViewModel() {
    private val mutableState = MutableStateFlow(PlayerUiState())
    val uiState = mutableState.asStateFlow()

    private var job: Job? = null
    private var key: Triple<String, String, String>? = null

    fun open(programmeId: String, dateId: String, contentId: String, selection: PlaybackSelection? = null) {
        val currentKey = Triple(programmeId, dateId, contentId)
        if (key == currentKey) return

        key = currentKey
        job?.cancel()
        mutableState.value = PlayerUiState()

        job = viewModelScope.launch {
            val accepted = selection?.takeIf {
                it.programmeId == programmeId && it.dateId == dateId && it.content.id == contentId &&
                    videoVariants(it.content).isNotEmpty()
            }
            // Pin the accepted item so background metadata refreshes cannot change playback or download identity.
            var selectedContent = accepted?.content
            var source: PlaybackSource? = null
            var recorder: PlaybackHistoryRecorder? = null
            var context = accepted?.accepted
            var programmeName = accepted?.programmeName
            var broadcastDate = accepted?.broadcastDate

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
                val content = selectedContent ?: resource.data?.firstOrNull { it.id == contentId }
                val variants = content?.let(::videoVariants).orEmpty()
                if (context == null && content != null) {
                    val programme = programmes.data?.firstOrNull { it.id == programmeId }
                    val date = dates.data?.firstOrNull { it.id == dateId }
                    if (programme != null && date != null) context = ProgrammeSelection(programme, date, content)
                }
                // Metadata may arrive after the source. Attach recording then without moving an already opened player.
                val resume = if (recorder == null && context != null) {
                    PlaybackHistoryRecorder(history, ViewingTarget.Online(requireNotNull(context)), viewModelScope)
                        .also { recorder = it }.initialize()
                } else {
                    0L
                }
                if (source == null && content != null && variants.isNotEmpty()) {
                    selectedContent = content
                    source =
                        PlaybackSource(
                            content.id,
                            content.title,
                            variants,
                            startPositionMs =
                            saved["positionMs"] ?: resume
                        )
                }
                if (programmeName == null) {
                    programmeName = programmes.data?.firstOrNull { it.id == programmeId }?.name
                }
                if (broadcastDate == null) broadcastDate = dates.data?.firstOrNull { it.id == dateId }?.date

                val error = when {
                    source != null -> null
                    resource.data != null -> AppError(ErrorKind.NoVideo, "该节目暂时无法播放")
                    else -> resource.error
                }

                PlayerUiState(
                    source == null && resource.data == null && resource.error == null,
                    source,
                    content,
                    error,
                    preferences.initialQuality,
                    programmeName ?: "节目",
                    broadcastDate,
                    context,
                    recorder
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
