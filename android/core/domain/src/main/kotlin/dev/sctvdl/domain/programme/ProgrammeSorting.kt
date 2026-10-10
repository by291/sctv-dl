package dev.sctvdl.domain.programme

import java.text.Collator
import java.util.Locale

fun sortProgrammes(programmes: List<Programme>, favourites: Set<String>, byName: Boolean): List<Programme> {
    val collator = Collator.getInstance(Locale.SIMPLIFIED_CHINESE)
    return programmes.sortedWith { left, right ->
        val group = (left.id !in favourites).compareTo(right.id !in favourites)
        if (group != 0) {
            group
        } else if (byName) {
            val name = collator.compare(left.name, right.name)
            if (name != 0) name else left.serviceOrder.compareTo(right.serviceOrder)
        } else {
            left.serviceOrder.compareTo(right.serviceOrder)
        }
    }
}
