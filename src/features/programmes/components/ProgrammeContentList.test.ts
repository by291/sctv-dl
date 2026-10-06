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
        quality: 'standard',
        videoNote: () => '流畅画质',
      },
    })
    const checkboxes = wrapper.findAll('[role="checkbox"]')
    await checkboxes[0]!.trigger('click')
    expect(wrapper.emitted('update:modelValue')).toEqual([[['1']]])
    await checkboxes[1]!.trigger('click')
    expect(wrapper.emitted('update:modelValue')).toEqual([[['1']]])
    wrapper.unmount()
  })
})
