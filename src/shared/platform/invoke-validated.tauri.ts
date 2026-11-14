import { invoke } from '@tauri-apps/api/core'

import { applicationErrorSchema } from '@shared/contracts/errors'

import type { z } from 'zod'

interface InvocationMessages {
  failure: string
  invalid: string
}

// Call a native command, validate its reply, and preserve diagnostic causes.
export async function invokeValidated<T>({
  command,
  parameters,
  schema,
  messages,
}: {
  command: string
  parameters: Record<string, unknown>
  schema: z.ZodType<T>
  messages: InvocationMessages
}): Promise<T> {
  let raw: unknown
  try {
    raw = await invoke(command, parameters)
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
