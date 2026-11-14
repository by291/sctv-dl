import { z } from 'zod'

import {
  idSchema,
  programmeSchema,
  programmeDateSchema,
  programmeContentSchema,
} from '@shared/contracts/programmes'

import { invokeAbortable } from '@/shared/platform/invoke-abortable.tauri'

import type { ProgrammeApi } from '@/shared/platform/ports'

function validatedId(value: string): string {
  const result = idSchema.safeParse(value)
  if (!result.success) {
    throw new Error('节目 ID 无效')
  }

  return result.data
}

// Read validated catalogue, broadcast, and content records over cancellable IPC.
export function createTauriProgrammeApi(): ProgrammeApi {
  return {
    programmes: (signal) =>
      invokeAbortable({
        command: 'list_programmes',
        parameters: {},
        schema: z.array(programmeSchema),
        signal,
      }),
    async dates(programmeId, signal) {
      return invokeAbortable({
        command: 'list_programme_dates',
        parameters: { programmeId: validatedId(programmeId) },
        schema: z.array(programmeDateSchema),
        signal,
      })
    },
    async contents(programmeId, dateId, signal) {
      return invokeAbortable({
        command: 'list_programme_contents',
        parameters: { programmeId: validatedId(programmeId), dateId: validatedId(dateId) },
        schema: z.array(programmeContentSchema),
        signal,
      })
    },
  }
}
