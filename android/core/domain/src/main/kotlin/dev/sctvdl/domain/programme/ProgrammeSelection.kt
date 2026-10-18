package dev.sctvdl.domain.programme

data class ContentRef(val programmeId: String, val dateId: String, val contentId: String)

/** Immutable accepted context; later metadata refreshes must not change an active selection. */
data class ProgrammeSelection(val programme: Programme, val broadcast: BroadcastDate, val content: ProgrammeContent) {
    val ref: ContentRef get() = ContentRef(programme.id, broadcast.id, content.id)
}
