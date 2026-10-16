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

export function createTauriProgrammeApi(): ProgrammeApi {
  return {
    programmes: (signal) =>
      invokeAbortable('list_programmes', {}, z.array(programmeSchema), signal),
    async dates(programmeId, signal) {
      return invokeAbortable(
        'list_programme_dates',
        { programmeId: validatedId(programmeId) },
        z.array(programmeDateSchema),
        signal,
      )
    },
    async contents(programmeId, dateId, signal) {
      return invokeAbortable(
        'list_programme_contents',
        { programmeId: validatedId(programmeId), dateId: validatedId(dateId) },
        z.array(programmeContentSchema),
        signal,
      )
    },
  }
}
