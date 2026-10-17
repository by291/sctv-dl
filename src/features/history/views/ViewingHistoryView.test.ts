// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { createPinia } from 'pinia'

import ViewingHistoryView from '@/features/history/views/ViewingHistoryView.vue'
import { useHistoryStore } from '@/features/history/stores/useHistoryStore'
import { createPlatformFixture } from '@/shared/platform/platform.test-support'
import { platformKey } from '@/shared/platform/usePlatform'
import ProgrammePreviewDialog from '@/features/programmes/components/ProgrammePreviewDialog.vue'

const entry = {
  content: { programmeId: '1', dateId: '2', contentId: '3' },
  programmeName: 'News',
  broadcastDate: '2026-10-17',
  title: 'Episode',
  cover: null,
  positionMs: 300000,
  durationMs: 600000,
  completed: false,
  viewedAt: '2026-10-17T00:00:00Z',
}
afterEach(() => vi.restoreAllMocks())

it('opens saved IDs without a catalogue and filters and deletes records without losing focus', async () => {
  const platform = createPlatformFixture()
  let entries = [
    entry,
    { ...entry, title: 'Second', content: { ...entry.content, contentId: '4' } },
  ]
  platform.history.list = async () => ({ entries, revision: 1, persisted: true, warning: null })
  platform.history.remove = async (content) => {
    entries = entries.filter((item) => item.content.contentId !== content.contentId)
  }

  const pinia = createPinia()
  await useHistoryStore(pinia).attach(platform.history)
  const wrapper = mount(ViewingHistoryView, {
    attachTo: document.body,
    global: {
      plugins: [pinia],
      provide: { [platformKey as symbol]: platform },
      stubs: { ProgrammePreviewDialog: true },
    },
  })
  const scroll = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  await wrapper.get('[aria-label="播放封面：Episode"]').trigger('click')
  expect(wrapper.findComponent(ProgrammePreviewDialog).props('reference')).toEqual(entry.content)
  expect(wrapper.findComponent(ProgrammePreviewDialog).props('input')?.metadata.title).toBe(
    'Episode',
  )
  await wrapper.get('input').setValue('Second')
  expect(wrapper.findAll('.history-card')).toHaveLength(1)
  await wrapper.get('input').setValue('')
  const remove = wrapper.get<HTMLButtonElement>('[aria-label="删除记录：Episode"]')
  remove.element.focus()
  await remove.trigger('click')
  await flushPromises()
  expect(wrapper.findAll('.history-card')).toHaveLength(1)
  expect(document.activeElement?.getAttribute('aria-label')).toBe('播放封面：Second')
  expect(scroll).toHaveBeenCalledWith(expect.objectContaining({ top: 0, behavior: 'instant' }))
  wrapper.unmount()
})

it('keeps playback available while a deletion fails', async () => {
  const platform = createPlatformFixture()
  platform.history.list = async () => ({
    entries: [entry],
    revision: 1,
    persisted: true,
    warning: null,
  })
  platform.history.remove = async () => {
    throw new Error('Storage unavailable')
  }

  const pinia = createPinia()
  await useHistoryStore(pinia).attach(platform.history)
  const wrapper = mount(ViewingHistoryView, {
    global: {
      plugins: [pinia],
      provide: { [platformKey as symbol]: platform },
      stubs: { ProgrammePreviewDialog: true },
    },
  })
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  await wrapper.get('[aria-label="删除记录：Episode"]').trigger('click')
  await flushPromises()
  expect(wrapper.text()).toContain('Storage unavailable')
  expect(wrapper.find('[aria-label="继续观看：Episode"]').exists()).toBe(true)
  wrapper.unmount()
})
