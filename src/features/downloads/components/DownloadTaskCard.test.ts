// @vitest-environment happy-dom
import { expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import { NDropdown, NModal, NProgress } from 'naive-ui'

import DownloadTaskCard from '@/features/downloads/components/DownloadTaskCard.vue'
import { createDownloadTaskFixture } from '@/shared/platform/platform.test-support'

const saved = {
  ...createDownloadTaskFixture(),
  state: 'completed' as const,
  fileAvailable: true,
  hasPartial: false,
  totalBytes: 4096,
  receivedBytes: 4096,
}

it('plays a saved cover and keeps completed transfers out of the progress display', async () => {
  const card = mount(DownloadTaskCard, { props: { task: saved, selected: false, busy: false } })
  expect(card.get('h2').text()).toBe(saved.metadata.title)
  expect(card.text()).not.toContain(saved.filename)
  expect(card.findComponent(NProgress).exists()).toBe(false)
  await card.get('button[aria-label="播放封面：Episode"]').trigger('click')
  expect(card.emitted('play')).toHaveLength(1)
  expect(card.emitted('action')).toBeUndefined()
  await card.setProps({ busy: true })
  expect(card.get('button[aria-label="播放封面：Episode"]').attributes('disabled')).toBeDefined()
  card.unmount()
})

it('confirms file deletion separately from removing a record and rejects a stale confirmation', async () => {
  const card = mount(DownloadTaskCard, { props: { task: saved, selected: false, busy: false } })
  card.getComponent(NDropdown).vm.$emit('select', 'deleteFile')
  await card.vm.$nextTick()
  expect(card.getComponent(NModal).props('show')).toBe(true)
  expect(card.emitted('action')).toBeUndefined()
  card.getComponent(NModal).vm.$emit('positive-click')
  expect(card.emitted('action')?.[0]).toEqual(['deleteFile'])
  card.getComponent(NDropdown).vm.$emit('select', 'remove')
  await card.vm.$nextTick()
  card.getComponent(NModal).vm.$emit('positive-click')
  expect(card.emitted('action')?.[1]).toEqual(['remove'])
  card.getComponent(NDropdown).vm.$emit('select', 'deleteFile')
  await card.setProps({ task: { ...saved, attemptId: 'new-attempt' } })
  card.getComponent(NModal).vm.$emit('positive-click')
  expect(card.emitted('action')).toHaveLength(2)
  card.unmount()
})

it('shows partial progress without a play affordance and confirms destructive restarts', async () => {
  const task = { ...saved, state: 'paused' as const, hasPartial: true, canResume: false }
  const card = mount(DownloadTaskCard, { props: { task, selected: false, busy: false } })
  expect(card.find('[aria-label="播放封面：Episode"]').exists()).toBe(false)
  expect(card.getComponent(NProgress).props('percentage')).toBe(99)
  await card.get('[aria-label="重新下载：news.mp4"]').trigger('click')
  expect(card.emitted('action')).toBeUndefined()
  card.getComponent(NModal).vm.$emit('positive-click')
  expect(card.emitted('action')?.[0]).toEqual(['restart'])
  card.unmount()
})
