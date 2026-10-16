// @vitest-environment happy-dom
import { expect, it } from 'vitest'
import { mount } from '@vue/test-utils'

import { usePlatform } from '@/shared/platform/usePlatform'

it('fails explicitly when features are mounted without their platform dependency', () => {
  expect(() =>
    mount(
      {
        setup() {
          usePlatform()

          return () => null
        },
      },
      {
        global: { config: { warnHandler: () => {} } },
      },
    ),
  ).toThrow('platform must be provided')
})
