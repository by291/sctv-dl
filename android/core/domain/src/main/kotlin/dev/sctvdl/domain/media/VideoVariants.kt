package dev.sctvdl.domain.media

import dev.sctvdl.domain.programme.ProgrammeContent

fun videoVariants(content: ProgrammeContent): List<VideoVariant> = buildList {
    content.standardUrl?.takeIf { it.isNotBlank() }?.let { add(VideoVariant(Quality.Standard, it)) }
    content.smoothUrl?.takeIf {
        it.isNotBlank() && it != content.standardUrl
    }?.let { add(VideoVariant(Quality.Smooth, it)) }
}

fun resolveVideo(content: ProgrammeContent, requested: Quality): VideoVariant? {
    val variants = videoVariants(content)
    return variants.firstOrNull { it.quality == requested } ?: variants.firstOrNull()
}
