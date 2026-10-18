import { invoke } from '@tauri-apps/api/core'

import { applicationErrorSchema } from '@shared/contracts/errors'

import type { z } from 'zod'

interface InvocationMessages {
  failure: string
  invalid: string
}

export async function invokeValidated<T>(
  command: string,
  args: Record<string, unknown>,
  schema: z.ZodType<T>,
  messages: InvocationMessages,
): Promise<T> {
  let raw: unknown
  try {
    raw = await invoke(command, args)
  } catch (cause) {
    const error = applicationErrorSchema.safeParse(cause)
    throw new Error(error.success ? error.data.message : messages.failure, { cause })
  }

  const result = schema.safeParse(raw)
  if (!result.success) {
    throw new Error(messages.invalid, { cause: result.error })
  }

  return result.data
}
