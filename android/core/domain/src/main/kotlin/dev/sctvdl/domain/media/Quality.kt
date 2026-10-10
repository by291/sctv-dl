package dev.sctvdl.domain.media

enum class Quality(val label: String) { Standard("标清"), Smooth("流畅") }
data class VideoVariant(val quality: Quality, val url: String)
