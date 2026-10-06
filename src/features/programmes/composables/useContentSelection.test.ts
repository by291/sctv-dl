import { describe, expect, it } from 'vitest'
import { effectScope, nextTick, ref } from 'vue'
import { useContentSelection } from './useContentSelection'
import type { ProgrammeContent } from '../types'

const full: ProgrammeContent = {
  id: '1',
  title: '栏目（2026.10.06）',
  cover: null,
  video: null,
  smoothVideo: 'https://fscgc.scgchc.com/a.mp4',
  publishedAt: null,
}
const missing: ProgrammeContent = { ...full, id: '2', title: '片段', smoothVideo: null }

describe('content selection', () => {
  it('selects only playable entries and recognizes full episodes by title', () => {
    const scope = effectScope()
    const selection = scope.run(() =>
      useContentSelection(ref([full, missing]), ref('栏目'), ref('2026-10-06')),
    )!
    selection.selectAll(true)
    expect(selection.selected.value).toEqual(['1'])
    expect(selection.fullIds.value).toEqual(['1'])
    expect(selection.hasVideo(full)).toBe(true)
    expect(selection.hasVideo(missing)).toBe(false)
    scope.stop()
  })

  it('clears old selection when the date changes its content list', async () => {
    const contents = ref([full])
    const scope = effectScope()
    const selection = scope.run(() =>
      useContentSelection(contents, ref('栏目'), ref('2026-10-06')),
    )!
    selection.selectAll(true)
    contents.value = [missing]
    await nextTick()
    expect(selection.selected.value).toEqual([])
    expect(selection.allSelected.value).toBe(false)
    scope.stop()
  })
})
