import { ref } from 'vue'

import { resumePosition } from '@shared/contracts/history'
import { errorMessage } from '@/shared/utils/errors'

import type { HistoryMetadata, HistorySample } from '@shared/contracts/history'
import type { HistoryPort } from '@/shared/platform/ports'
import type {
  PlaybackRestore,
  PlaybackSampleReason,
  PlaybackSnapshot,
} from '@/features/programmes/model/playback-state'

export function usePlaybackHistory(
  port: HistoryPort,
  metadata: HistoryMetadata,
  capture?: () => PlaybackSnapshot | null,
) {
  const warning = ref('')
  let sessionId: string | null = null
  let sequence = 0
  let latest: PlaybackSnapshot | null = null
  let lastProgressWrite = -Infinity
  let lastProgressPosition = -1
  let pending: HistorySample | null = null
  let queue = Promise.resolve()
  let disposed = false
  let disposal: Promise<void> | null = null

  async function begin(): Promise<PlaybackRestore> {
    try {
      const session = await port.begin(metadata)
      if (disposed) {
        await port.end(session.id)

        return { positionMs: 0, speed: 1, playing: false }
      }

      sessionId = session.id
      warning.value = ''

      return {
        positionMs: session.entry ? resumePosition(session.entry) : 0,
        speed: 1,
        playing: false,
      }
    } catch (cause) {
      warning.value = errorMessage(cause)

      return { positionMs: 0, speed: 1, playing: false }
    }
  }

  const ready = begin()

  function enqueue(sample: HistorySample) {
    queue = queue.then(async () => {
      if (!sessionId) {
        return
      }

      try {
        const result = await port.record(sessionId, sample)
        if (!result.persisted) {
          pending = sample
          warning.value = '观看记录尚未保存到设备，可重试保存。'
        } else {
          pending = null
          warning.value = ''
        }
      } catch (cause) {
        pending = sample
        warning.value = errorMessage(cause)
      }
    })

    return queue
  }

  function save() {
    if (!latest || !sessionId || disposed) {
      return queue
    }

    const { positionMs, durationMs, ended } = latest
    lastProgressWrite = Date.now()
    lastProgressPosition = positionMs

    return enqueue({ positionMs, durationMs, ended, sequence: ++sequence })
  }

  function update(value: PlaybackSnapshot, reason: PlaybackSampleReason) {
    if (
      disposed ||
      !value.initialized ||
      !Number.isFinite(value.positionMs) ||
      value.positionMs < 0
    ) {
      return
    }

    latest = value
    if (reason === 'seek' || reason === 'pause' || reason === 'ended') {
      void save()
    } else if (
      reason === 'progress' &&
      value.positionMs > lastProgressPosition &&
      Date.now() - lastProgressWrite >= 5000
    ) {
      void save()
    }
  }

  async function captureAndSave() {
    if (disposed) {
      return
    }

    const value = capture?.()
    // An unsettled current player must not replace the last usable sample.
    if (value) {
      update(value, 'state')
    }

    await save()
  }

  async function retry() {
    if (disposed) {
      return
    }

    await queue
    if (disposed) {
      return
    }

    if (!sessionId) {
      await begin()
    }

    if (disposed) {
      return
    }

    // A failed attempt retains its sequence; retries are not newer observations.
    if (pending) {
      await enqueue(pending)
    } else {
      await save()
    }
  }

  function dispose() {
    if (disposal) {
      return disposal
    }

    disposed = true
    disposal = (async () => {
      await ready
      await queue
      if (sessionId) {
        try {
          await port.end(sessionId)
        } catch (cause) {
          warning.value = errorMessage(cause)
        }

        sessionId = null
      }
    })()

    return disposal
  }

  return { ready, warning, update, captureAndSave, retry, dispose, settled: () => queue }
}
