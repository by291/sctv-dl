import { expect, it } from 'vitest'

import { availableDownloadActions } from '@/features/downloads/model/download-actions'
import { createDownloadTaskFixture } from '@/shared/platform/platform.test-support'

it('offers pause for active transfers and restart rather than resume for unsafe partials', () => {
  const task = createDownloadTaskFixture()
  expect(availableDownloadActions(task)).toEqual(['pause', 'cancel'])
  expect(availableDownloadActions({ ...task, state: 'paused' })).toEqual(['restart', 'cancel'])
  expect(availableDownloadActions({ ...task, state: 'interrupted', canResume: true })).toEqual([
    'resume',
    'restart',
    'cancel',
  ])
  expect(availableDownloadActions({ ...task, state: 'pausing' })).toEqual([])
})
it('separates completed-file actions from record-only removal', () => {
  const task = createDownloadTaskFixture()
  expect(
    availableDownloadActions({
      ...task,
      state: 'completed',
      fileAvailable: true,
      hasPartial: false,
    }),
  ).toEqual(['openFile', 'revealFile', 'deleteFile', 'remove'])
  expect(availableDownloadActions({ ...task, state: 'missing', hasPartial: false })).toEqual([
    'restart',
    'remove',
  ])
})
