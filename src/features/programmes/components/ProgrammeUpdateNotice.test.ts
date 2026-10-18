// @vitest-environment happy-dom
import { expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import ProgrammeUpdateNotice from '@/features/programmes/components/ProgrammeUpdateNotice.vue'

it('does not insert a notice while cached content is refreshed without changes', async () => {
  const wrapper = mount(ProgrammeUpdateNotice, {
    props: { cached: true, fetchedAt: '2026-10-17T00:00:00Z' },
  })

  expect(wrapper.find('[aria-label="节目数据状态"]').exists()).toBe(false)

  await wrapper.setProps({ cached: false, fetchedAt: '2026-10-18T00:00:00Z' })

  expect(wrapper.find('[aria-label="节目数据状态"]').exists()).toBe(false)
  wrapper.unmount()
})

it('still explains cached content and offers retry when background refresh fails', async () => {
  const wrapper = mount(ProgrammeUpdateNotice, {
    props: { cached: true, refreshError: 'Offline' },
  })

  expect(wrapper.text()).toContain('缓存')
  expect(wrapper.text()).toContain('Offline')
  await wrapper.get('button').trigger('click')
  expect(wrapper.emitted('retry')).toHaveLength(1)
  wrapper.unmount()
})

it('keeps an update visible but disables applying it during an active interaction', async () => {
  const wrapper = mount(ProgrammeUpdateNotice, {
    props: {
      pending: true,
      held: true,
      refreshError: 'Offline',
      cached: true,
      fetchedAt: '2026-10-17T00:00:00Z',
    },
  })
  expect(wrapper.text()).toContain('发现新内容')
  expect(wrapper.text()).toContain('缓存')
  expect(wrapper.text()).toContain('Offline')
  expect(wrapper.get('button').attributes('disabled')).toBeDefined()
  await wrapper.setProps({ held: false })
  await wrapper.get('button').trigger('click')
  expect(wrapper.emitted('accept')).toHaveLength(1)
  wrapper.unmount()
})
