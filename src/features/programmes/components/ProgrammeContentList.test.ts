// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import ProgrammeContentList from './ProgrammeContentList.vue'
import type { ProgrammeContent } from '../types'

describe('programme content selection UI', () => {
  it('emits selected IDs through the checkbox group and disables missing videos', async () => {
    const content: ProgrammeContent = {
      id: '1',
      title: '整期',
      cover: null,
      video: null,
      smoothVideo: 'https://fscgc.scgchc.com/a.mp4',
      publishedAt: null,
    }
    const wrapper = mount(ProgrammeContentList, {
      props: {
        modelValue: [],
        contents: [content, { ...content, id: '2', smoothVideo: null }],
        fullIds: ['1'],
      },
    })
    const checkboxes = wrapper.findAll('[role="checkbox"]')
    await checkboxes[0]!.trigger('click')
    expect(wrapper.emitted('update:modelValue')).toEqual([[['1']]])
    await checkboxes[1]!.trigger('click')
    expect(wrapper.emitted('update:modelValue')).toEqual([[['1']]])
    const downloadButtons = wrapper
      .findAll('button')
      .filter((button) => button.attributes('aria-label')?.startsWith('下载'))
    expect(downloadButtons).toHaveLength(2)
    expect(downloadButtons[1]!.attributes('disabled')).toBeDefined()
    wrapper.unmount()
  })
})
