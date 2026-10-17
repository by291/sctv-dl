import { describe, expect, it } from 'vitest'

import {
  downloadActionRequestSchema,
  downloadEventSchema,
  downloadSnapshotSchema,
  downloadTaskSchema,
} from './downloads.ts'

const task = {
  id: 'task',
  attemptId: 'attempt',
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  filename: 'clip.mp4',
  quality: 'standard',
  state: 'interrupted',
  receivedBytes: 100,
  totalBytes: 1000,
  error: null,
  revision: 4,
  createdAt: '2026-10-17T00:00:00.000Z',
  metadata: {
    content: { programmeId: '1', dateId: '2', contentId: '3' },
    programmeName: 'News',
    broadcastDate: '2026-10-17',
    title: 'Evening',
    cover: null,
  },
  canResume: true,
  fileAvailable: false,
  hasPartial: true,
}

describe('durable native download contracts', () => {
  it('accepts interrupted recovery and revisioned removal events without private paths', () => {
    expect(downloadTaskSchema.parse(task)).toEqual(task)
    expect(
      downloadSnapshotSchema.parse({ epoch: 'process', revision: 8, tasks: [task] }).tasks,
    ).toHaveLength(1)
    expect(
      downloadEventSchema.parse({ epoch: 'process', revision: 9, kind: 'remove', taskId: 'task' })
        .kind,
    ).toBe('remove')
  })

  it('rejects arbitrary paths, unknown actions and missing attempt guards', () => {
    expect(
      downloadActionRequestSchema.safeParse({
        taskId: 'task',
        attemptId: 'attempt',
        action: 'deleteFile',
        path: '/tmp/file',
      }).success,
    ).toBe(false)
    expect(
      downloadActionRequestSchema.safeParse({
        taskId: 'task',
        attemptId: 'attempt',
        action: 'execute',
      }).success,
    ).toBe(false)
    expect(downloadActionRequestSchema.safeParse({ taskId: 'task', action: 'pause' }).success).toBe(
      false,
    )
  })
})
