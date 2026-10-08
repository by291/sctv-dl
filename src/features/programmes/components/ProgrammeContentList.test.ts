// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import ProgrammeContentList from './ProgrammeContentList.vue'
import type { ProgrammeContent } from '../types'

describe('programme content selection UI', () => {
  it('reveals a complete title without previewing, downloading, or selecting the content', async () => {
    const title = 'A long programme title '.repeat(12).trim()
    const wrapper = mount(ProgrammeContentList, {
      attachTo: document.body,
      props: {
        modelValue: [],
        contents: [
          {
            id: '1',
            title,
            cover: null,
            video: null,
            smoothVideo: null,
            publishedAt: null,
          },
        ],
        fullIds: [],
      },
    })

    try {
      await wrapper.get('button.content-title').trigger('click')

      await vi.waitFor(() => {
        expect(document.querySelector('.content-title-popover')?.textContent?.trim()).toBe(title)
      })
      expect(wrapper.emitted('preview')).toBeUndefined()
      expect(wrapper.emitted('download')).toBeUndefined()
      expect(wrapper.emitted('update:modelValue')).toBeUndefined()

      await wrapper.get('button.content-title').trigger('keydown', { key: 'Escape' })

      await vi.waitFor(() => {
        const popover = document.querySelector<HTMLElement>('.content-title-popover')

        expect(!popover || popover.style.display === 'none').toBe(true)
      })
    } finally {
      wrapper.unmount()
    }
  })

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
