import { describe, expect, it } from 'vitest'

import {
  downloadRequestSchema,
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

describe('download preparation contracts', () => {
  it('limits distinct batch IDs and refuses caller-supplied file locations', () => {
    const request = { programmeId: '1', dateId: '2', contentIds: ['3', '3'], quality: 'standard' }
    expect(downloadRequestSchema.parse(request).contentIds).toEqual(['3'])
    expect(
      downloadRequestSchema.safeParse({ ...request, url: 'https://example.com/a.mp4' }).success,
    ).toBe(false)
    expect(
      downloadRequestSchema.safeParse({
        ...request,
        contentIds: Array.from({ length: 101 }, (_, i) => String(i)),
      }).success,
    ).toBe(false)
  })
})

describe('download progress contracts', () => {
  it('preserves unknown transfer totals and rejects negative progress', () => {
    const task = {
      id: 'task-1',
      attemptId: 'attempt-1',
      createdAt: '2026-10-17T00:00:00Z',
      metadata: {
        content: { programmeId: '1', dateId: '2', contentId: '3' },
        programmeName: 'News',
        broadcastDate: '2026-10-17',
        title: 'News',
        cover: null,
      },
      canResume: false,
      fileAvailable: false,
      hasPartial: true,
      content: { programmeId: '1', dateId: '2', contentId: '3' },
      filename: 'news.mp4',
      quality: 'standard',
      state: 'running',
      receivedBytes: 10,
      totalBytes: null,
      error: null,
      revision: 1,
    }
    expect(downloadTaskSchema.parse(task).totalBytes).toBeNull()
    expect(downloadTaskSchema.safeParse({ ...task, receivedBytes: -1 }).success).toBe(false)
  })
})
