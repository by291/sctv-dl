import { z } from 'zod'

import type { ProgrammeContent } from '@/features/programmes/model/programme'

export type ContentSortOrder = 'asc' | 'desc'

interface PublicationTime {
  timestamp: number
  datetime: string
  label: string
}

interface ProgrammeContentRow {
  content: ProgrammeContent
  fullEpisode: boolean
  publication: PublicationTime | null
}

const publicationSchema = z.iso.datetime({ offset: true, local: true })
const publicationFormat = new Intl.DateTimeFormat('zh-CN', {
  timeZone: 'Asia/Shanghai',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
  hourCycle: 'h23',
})

function publicationTime(value: string | null): PublicationTime | null {
  const parsed = publicationSchema.safeParse(value?.trim().replace(' ', 'T'))

  if (!parsed.success) {
    return null
  }

  // Upstream timestamps without an offset use the programme service's China timezone.
  const datetime = /(?:Z|[+-]\d{2}:\d{2})$/.test(parsed.data) ? parsed.data : `${parsed.data}+08:00`
  const timestamp = Date.parse(datetime)

  return {
    timestamp,
    datetime: new Date(timestamp).toISOString(),
    label: publicationFormat.format(timestamp).replaceAll('/', '-'),
  }
}

export function programmeContentRows(
  contents: readonly ProgrammeContent[],
  fullIds: readonly string[],
  order: ContentSortOrder,
): ProgrammeContentRow[] {
  const full = new Set(fullIds)
  const rows = contents.map((content) => ({
    content,
    fullEpisode: full.has(content.id),
    publication: publicationTime(content.publishedAt),
  }))

  return rows.sort((left, right) => {
    if (left.fullEpisode !== right.fullEpisode) {
      return left.fullEpisode ? -1 : 1
    }

    if (left.fullEpisode) {
      return 0
    }

    // Unknown times follow dated clips; ties retain the upstream order.
    if (!left.publication || !right.publication) {
      return left.publication ? -1 : right.publication ? 1 : 0
    }

    const difference = left.publication.timestamp - right.publication.timestamp

    return order === 'asc' ? difference : -difference
  })
}
