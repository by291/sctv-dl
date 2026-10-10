import { describe, expect, it } from 'vitest'
import { effectScope, nextTick, ref } from 'vue'

import { useFeaturedProgramme } from '@/features/programmes/composables/useFeaturedProgramme'

import type { Programme } from '@/features/programmes/model/programme'

const catalogue: Programme[] = ['1', '2', '3'].map((id) => ({
  id,
  name: `Programme ${id}`,
  cover: null,
}))

describe('featured programme selection', () => {
  it('selects from the loaded catalogue without preferring a fixed ID', async () => {
    const programmes = ref<Programme[]>([])
    const scope = effectScope()
    const selection = scope.run(() => useFeaturedProgramme(programmes, () => 0.8))!

    expect(selection.featured.value).toBeNull()
    programmes.value = catalogue
    await nextTick()

    expect(selection.featured.value?.id).toBe('3')
    expect(selection.canChange.value).toBe(true)
    scope.stop()
  })

  it('excludes the current programme when choosing another', () => {
    const scope = effectScope()
    const selection = scope.run(() => useFeaturedProgramme(ref(catalogue), () => 0))!

    expect(selection.featured.value?.id).toBe('1')
    selection.chooseAnother()
    expect(selection.featured.value?.id).toBe('2')
    selection.chooseAnother()
    expect(selection.featured.value?.id).toBe('1')
    scope.stop()
  })

  it('retains the selection and uses refreshed programme metadata', async () => {
    const programmes = ref(catalogue)
    const scope = effectScope()
    const selection = scope.run(() => useFeaturedProgramme(programmes, () => 0.8))!

    programmes.value = catalogue.map((item) => ({ ...item, name: `Updated ${item.id}` }))
    await nextTick()

    expect(selection.featured.value?.id).toBe('3')
    expect(selection.featured.value?.name).toBe('Updated 3')
    scope.stop()
  })

  it('selects an available replacement if the current programme is removed', async () => {
    const programmes = ref(catalogue)
    const scope = effectScope()
    const selection = scope.run(() => useFeaturedProgramme(programmes, () => 0.8))!

    programmes.value = catalogue.slice(0, 2)
    await nextTick()

    expect(selection.featured.value?.id).toBe('2')
    programmes.value = []
    await nextTick()
    expect(selection.featured.value).toBeNull()
    scope.stop()
  })

  it('handles an empty catalogue and disables changing a single programme', async () => {
    const programmes = ref<Programme[]>([])
    const scope = effectScope()
    const selection = scope.run(() => useFeaturedProgramme(programmes, () => 0))!

    selection.chooseAnother()
    expect(selection.featured.value).toBeNull()
    expect(selection.canChange.value).toBe(false)

    programmes.value = [catalogue[0]!]
    await nextTick()
    selection.chooseAnother()

    expect(selection.featured.value?.id).toBe('1')
    expect(selection.canChange.value).toBe(false)
    scope.stop()
  })
})
