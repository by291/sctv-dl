// @vitest-environment happy-dom
import { expect, it } from 'vitest'
import { startWithRecovery } from '@/platform/startup'

it('offers a recoverable startup failure and prevents duplicate retry attempts', async () => {
  const root = document.createElement('div')
  let attempts = 0
  await startWithRecovery(root, async () => {
    if (++attempts === 1) {
      throw new Error('initialization failed')
    }

    root.textContent = 'application mounted'
  })
  expect(root.querySelector('[role="alert"]')).not.toBeNull()
  const retry = root.querySelector('button')!
  retry.click()
  retry.click()
  await Promise.resolve()
  expect(attempts).toBe(2)
  expect(root.textContent).toBe('application mounted')
})
