export function isFullEpisode(
  title: string,
  programmeName: string,
  broadcastDate: string | null,
): boolean {
  if (!programmeName || !broadcastDate) {
    return false
  }

  const date = broadcastDate.replaceAll('-', '.')
  const titles = [`${programmeName}（${date}）`, `${programmeName}(${date})`]

  // Match the programme and broadcast date; list position does not identify a full episode.
  return titles.includes(title.replace(/\s/g, ''))
}
