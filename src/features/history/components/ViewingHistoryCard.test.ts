// @vitest-environment happy-dom
import { expect, it } from 'vitest'
import { mount } from '@vue/test-utils'

import ViewingHistoryCard from '@/features/history/components/ViewingHistoryCard.vue'

it('separates playback and removal and presents completed progress truthfully', async () => {
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
  const wrapper = mount(ViewingHistoryCard, { props: { entry } })
  expect(wrapper.text()).toContain('5:00')
  await wrapper.get('[aria-label="继续观看：Episode"]').trigger('click')
  expect(wrapper.emitted('play')?.[0]).toEqual([entry])
  await wrapper.get('button[aria-label="播放封面：Episode"]').trigger('click')
  expect(wrapper.emitted('play')?.[1]).toEqual([entry])
  expect(wrapper.emitted('remove')).toBeUndefined()
  await wrapper.get('[aria-label="删除记录：Episode"]').trigger('click')
  expect(wrapper.emitted('remove')?.[0]).toEqual([entry])
  await wrapper.setProps({ entry: { ...entry, completed: true } })
  expect(wrapper.text()).toContain('已看完')
  expect(wrapper.find('[aria-label="重新播放：Episode"]').exists()).toBe(true)
  wrapper.unmount()
})
