import type {
  DownloadActionRequest,
  DownloadActionResult,
  DownloadEvent,
  DownloadSnapshot,
  DownloadTask,
} from '@shared/contracts/downloads'

export interface DownloadTaskState {
  tasks: DownloadTask[]
  epoch: string | null
  snapshotRevision: number
  retiredEpochs: Set<string>
  taskEventRevisions: Map<string, number>
  removedTaskIds: Set<string>
}

export function createDownloadTaskState(): DownloadTaskState {
  return {
    tasks: [],
    epoch: null,
    snapshotRevision: -1,
    retiredEpochs: new Set(),
    taskEventRevisions: new Map(),
    removedTaskIds: new Set(),
  }
}

export function resetDownloadObservation(state: DownloadTaskState): void {
  state.epoch = null
  state.snapshotRevision = -1
  state.retiredEpochs.clear()
  state.taskEventRevisions.clear()
  state.removedTaskIds.clear()
}

function mergeTask(state: DownloadTaskState, task: DownloadTask): void {
  if (state.removedTaskIds.has(task.id)) {
    return
  }

  const index = state.tasks.findIndex((value) => value.id === task.id)
  const previous = state.tasks[index]
  if (previous && previous.revision >= task.revision) {
    return
  }

  if (index < 0) {
    state.tasks.push(task)
  } else {
    state.tasks[index] = task
  }
}

function useEpoch(state: DownloadTaskState, next: string): boolean {
  if (state.retiredEpochs.has(next)) {
    return false
  }

  if (state.epoch === next) {
    return true
  }

  if (state.epoch !== null) {
    state.retiredEpochs.add(state.epoch)
  }

  state.epoch = next
  state.tasks = []
  state.taskEventRevisions.clear()
  state.removedTaskIds.clear()
  state.snapshotRevision = -1

  return true
}

export function applyDownloadSnapshot(state: DownloadTaskState, snapshot: DownloadSnapshot): void {
  // A snapshot started before a process replacement cannot switch us back.
  if (state.epoch !== null && state.epoch !== snapshot.epoch) {
    return
  }

  if (!useEpoch(state, snapshot.epoch) || snapshot.revision < state.snapshotRevision) {
    return
  }

  const snapshotTaskIds = new Set(snapshot.tasks.map((task) => task.id))
  state.tasks = state.tasks.filter(
    (task) =>
      snapshotTaskIds.has(task.id) ||
      (state.taskEventRevisions.get(task.id) ?? -1) > snapshot.revision,
  )
  for (const task of snapshot.tasks) {
    if ((state.taskEventRevisions.get(task.id) ?? -1) <= snapshot.revision) {
      mergeTask(state, task)
    }
  }

  state.snapshotRevision = snapshot.revision
}

export function applyDownloadEvent(state: DownloadTaskState, event: DownloadEvent): void {
  if (!useEpoch(state, event.epoch) || event.revision <= state.snapshotRevision) {
    return
  }

  const taskId = event.kind === 'upsert' ? event.task.id : event.taskId
  if ((state.taskEventRevisions.get(taskId) ?? -1) >= event.revision) {
    return
  }

  state.taskEventRevisions.set(taskId, event.revision)
  if (event.kind === 'remove') {
    removeTask(state, taskId)
  } else {
    mergeTask(state, event.task)
  }
}

function removeTask(state: DownloadTaskState, taskId: string): void {
  // IDs are never reused within an epoch. A tombstone also fences command removals,
  // which have no event revision, against delayed snapshots and command results.
  state.removedTaskIds.add(taskId)
  state.tasks = state.tasks.filter((task) => task.id !== taskId)
}

export function applyDownloadCommandResult(
  state: DownloadTaskState,
  taskId: string,
  action: DownloadActionRequest['action'],
  result: DownloadActionResult,
): void {
  if (result.kind !== 'applied') {
    return
  }

  if (result.task) {
    mergeTask(state, result.task)
  } else if (action === 'remove') {
    removeTask(state, taskId)
  }
}
