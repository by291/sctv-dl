package dev.sctvdl.feature.programmes.archive

import dev.sctvdl.domain.media.videoVariants
import dev.sctvdl.domain.programme.ProgrammeContent

internal fun selectableIds(contents: List<ProgrammeContent>): Set<String> = contents.filter {
    videoVariants(it).isNotEmpty()
}.map { it.id }.toSet()
