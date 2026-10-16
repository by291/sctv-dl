import { z } from 'zod'

import {
  idSchema,
  programmeSchema,
  programmeDateSchema,
  programmeContentSchema,
} from '@shared/contracts/programmes'
import { createClientApi } from '@/shared/platform/client-api'

import type { ProgrammeApi } from '@/shared/platform/ports'

export type { ProgrammeApi } from '@/shared/platform/ports'

export function createProgrammeApi(
  base = '/client-api/v1',
  fetcher: typeof fetch = fetch,
): ProgrammeApi {
  const request = createClientApi(base, fetcher)

  return {
    programmes: (signal) => request('/programmes', z.array(programmeSchema), { signal }),
    dates: async (programmeId, signal) =>
      request(`/programmes/${idSchema.parse(programmeId)}/dates`, z.array(programmeDateSchema), {
        signal,
      }),
    contents: async (programmeId, dateId, signal) =>
      request(
        `/programmes/${idSchema.parse(programmeId)}/dates/${idSchema.parse(dateId)}/contents`,
        z.array(programmeContentSchema),
        { signal },
      ),
  }
}
