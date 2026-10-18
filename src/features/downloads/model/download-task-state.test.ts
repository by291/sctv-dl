import { expect, it } from 'vitest'

import {
  createDownloadTaskState,
  applyDownloadSnapshot,
  applyDownloadEvent,
  applyDownloadCommandResult,
} from '@/features/downloads/model/download-task-state'
import { createDownloadTaskFixture } from '@/shared/platform/platform.test-support'

it('retains events newer than a delayed snapshot while replacing older snapshot rows', () => {
  const state = createDownloadTaskState()
  const task = createDownloadTaskFixture()
  applyDownloadSnapshot(state, { epoch: 'one', revision: 2, tasks: [task] })
  const newTask = { ...task, id: 'new', revision: 5 }
  applyDownloadEvent(state, { kind: 'upsert', epoch: 'one', revision: 5, task: newTask })

  applyDownloadSnapshot(state, { epoch: 'one', revision: 4, tasks: [] })
  applyDownloadSnapshot(state, { epoch: 'one', revision: 3, tasks: [task] })

  expect(state.tasks).toEqual([newTask])
})

it('keeps command removals fenced against later snapshots, events and command responses', () => {
  const state = createDownloadTaskState()
  const task = createDownloadTaskFixture()
  applyDownloadSnapshot(state, { epoch: 'one', revision: 2, tasks: [task] })

  applyDownloadCommandResult(state, task.id, 'remove', { kind: 'applied', task: null })
  applyDownloadSnapshot(state, { epoch: 'one', revision: 3, tasks: [task] })
  applyDownloadEvent(state, {
    kind: 'upsert',
    epoch: 'one',
    revision: 4,
    task: { ...task, revision: 4 },
  })
  applyDownloadCommandResult(state, task.id, 'pause', {
    kind: 'applied',
    task: { ...task, revision: 5, state: 'paused' },
  })

  expect(state.tasks).toEqual([])
})

it('resets removal fences for a new process and rejects retired epochs and snapshots', () => {
  const state = createDownloadTaskState()
  const task = createDownloadTaskFixture()
  applyDownloadSnapshot(state, { epoch: 'one', revision: 2, tasks: [task] })
  applyDownloadEvent(state, { kind: 'remove', epoch: 'one', revision: 3, taskId: task.id })
  const replacement = { ...task, attemptId: 'replacement', revision: 1 }

  applyDownloadEvent(state, { kind: 'upsert', epoch: 'two', revision: 1, task: replacement })
  applyDownloadSnapshot(state, { epoch: 'one', revision: 4, tasks: [] })
  applyDownloadEvent(state, { kind: 'remove', epoch: 'one', revision: 5, taskId: task.id })

  expect(state.tasks).toEqual([replacement])
})

it('keeps a newer attempt when an earlier command response arrives late', () => {
  const state = createDownloadTaskState()
  const task = createDownloadTaskFixture()
  const replacement = { ...task, attemptId: 'replacement', revision: 5 }
  applyDownloadSnapshot(state, { epoch: 'one', revision: 5, tasks: [replacement] })

  applyDownloadCommandResult(state, task.id, 'pause', {
    kind: 'applied',
    task: { ...task, revision: 4, state: 'paused' },
  })

  expect(state.tasks).toEqual([replacement])
})
