import { expect, it } from 'vitest'

import { downloadActionConfirmation } from '@/features/downloads/model/download-action-presentation'
import { createDownloadTaskFixture } from '@/shared/platform/platform.test-support'

it.each(['restart', 'cancel'] as const)(
  'confirms single %s only for partial data while always confirming its batch effects',
  (action) => {
    const task = createDownloadTaskFixture()

    expect(downloadActionConfirmation(action, { kind: 'single', task })).not.toBeNull()
    expect(
      downloadActionConfirmation(action, { kind: 'single', task: { ...task, hasPartial: false } }),
    ).toBeNull()
    expect(downloadActionConfirmation(action, { kind: 'batch', count: 2 })).not.toBeNull()
  },
)

it.each(['remove', 'deleteFile'] as const)(
  'confirms %s for both single and batch actions',
  (action) => {
    const task = createDownloadTaskFixture()

    expect(downloadActionConfirmation(action, { kind: 'single', task })).not.toBeNull()
    expect(downloadActionConfirmation(action, { kind: 'batch', count: 1 })).not.toBeNull()
  },
)

it.each(['pause', 'resume', 'openFile', 'revealFile'] as const)(
  'performs %s without a confirmation',
  (action) => {
    const task = createDownloadTaskFixture()

    expect(downloadActionConfirmation(action, { kind: 'single', task })).toBeNull()
    expect(downloadActionConfirmation(action, { kind: 'batch', count: 2 })).toBeNull()
  },
)
