package dev.sctvdl.domain

data class ProgrammeContent(
    val id: String,
    val title: String,
    val coverUrl: String? = null,
    val standardUrl: String? = null,
    val smoothUrl: String? = null,
    val publishedAt: String? = null
)
