package dev.sctvdl.player.ui

internal fun playbackTime(milliseconds: Long?): String {
    if (milliseconds == null) return "--:--"
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    val remainder = (seconds % 60).toString().padStart(2, '0')
    val minutes = seconds / 60
    return if (minutes <
        60
    ) {
        "$minutes:$remainder"
    } else {
        "${minutes / 60}:${(minutes % 60).toString().padStart(2, '0')}:$remainder"
    }
}
