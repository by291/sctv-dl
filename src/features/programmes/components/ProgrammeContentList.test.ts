// @vitest-environment happy-dom
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import ProgrammeContentList from '@/features/programmes/components/ProgrammeContentList.vue'
import type { ProgrammeContent } from '@/features/programmes/model/programme'

describe('programme content selection UI', () => {
  it('separates full episodes from clips while keeping clip sorting within its section', async () => {
    const content: ProgrammeContent = {
      id: 'full',
      title: 'Full episode',
      cover: null,
      video: 'https://fscgc.scgchc.com/a.mp4',
      smoothVideo: null,
      publishedAt: '2026-10-10 18:30:00',
    }
    const wrapper = mount(ProgrammeContentList, {
      props: {
        modelValue: [],
        contents: [
          { ...content, id: 'late', title: 'Later clip', publishedAt: '2026-10-10 18:55:00' },
          content,
          { ...content, id: 'early', title: 'Earlier clip', publishedAt: '2026-10-10 18:41:00' },
        ],
        fullIds: ['full'],
      },
    })

    try {
      const fullEpisodes = wrapper.get('section[aria-label="整期节目"]')
      const clips = wrapper.get('section[aria-label="节目片段"]')
      const clipTitles = () => clips.findAll('.content-title').map((title) => title.text())

      expect(fullEpisodes.findAll('article')).toHaveLength(1)
      expect(fullEpisodes.get('.content-title').text()).toBe(content.title)
      expect(clipTitles()).toEqual(['Earlier clip', 'Later clip'])
      await fullEpisodes.get('[role="checkbox"]').trigger('click')
      expect(wrapper.emitted('update:modelValue')).toEqual([[['full']]])
      await fullEpisodes.get('.content-thumbnail').trigger('click')
      expect(wrapper.emitted('preview')).toEqual([[content]])

      await clips.get('.content-sort').trigger('click')
      expect(wrapper.emitted('update:sortOrder')).toEqual([['desc']])
      await wrapper.setProps({ sortOrder: 'desc' })
      expect(clipTitles()).toEqual(['Later clip', 'Earlier clip'])
      expect(fullEpisodes.get('.content-title').text()).toBe(content.title)
      await wrapper.setProps({ fullIds: [] })
      expect(wrapper.find('section[aria-label="整期节目"]').exists()).toBe(false)
      expect(clips.findAll('article')).toHaveLength(3)

      await wrapper.setProps({ contents: [content], fullIds: ['full'] })
      expect(wrapper.find('section[aria-label="节目片段"]').exists()).toBe(false)
      expect(wrapper.find('.content-sort').exists()).toBe(false)
    } finally {
      wrapper.unmount()
    }
  })

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
