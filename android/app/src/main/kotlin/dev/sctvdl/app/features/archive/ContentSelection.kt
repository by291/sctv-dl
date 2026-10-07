package dev.sctvdl.app.features.archive

import dev.sctvdl.domain.ProgrammeContent
import dev.sctvdl.domain.videoVariants

fun selectableIds(contents: List<ProgrammeContent>): Set<String> = contents.filter {
    videoVariants(it).isNotEmpty()
}.map { it.id }.toSet()
