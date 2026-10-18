package dev.sctvdl.app.navigation

import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.navigation3.scene.Scene
import androidx.navigationevent.NavigationEvent
import dev.sctvdl.design.theme.PAGE_TRANSITION_DURATION_MILLIS

internal const val PRIMARY_DESTINATION_KEY = "dev.sctvdl.app.navigation.primaryDestination"
private const val PRIMARY_EXIT_MILLIS = 90
private const val PRIMARY_ENTER_MILLIS = 160
internal const val PRIMARY_TRANSITION_MILLIS = PRIMARY_EXIT_MILLIS + PRIMARY_ENTER_MILLIS

internal fun <T : Any> AnimatedContentTransitionScope<Scene<T>>.destinationTransition(
    primaryDistance: Int,
    pageDistance: Int,
    pop: Boolean,
    edge: Int? = null
): ContentTransform {
    val changesPrimaryDestination = initialState.metadata[PRIMARY_DESTINATION_KEY] !=
        targetState.metadata[PRIMARY_DESTINATION_KEY]
    val direction = when {
        edge == NavigationEvent.EDGE_RIGHT -> 1
        edge == NavigationEvent.EDGE_LEFT -> -1
        changesPrimaryDestination -> {
            val from = initialState.metadata[PRIMARY_DESTINATION_KEY] as Int
            val to = targetState.metadata[PRIMARY_DESTINATION_KEY] as Int
            if (to > from) 1 else -1
        }
        pop -> -1
        else -> 1
    }
    if (changesPrimaryDestination) {
        val enter = slideInHorizontally(
            tween(PRIMARY_ENTER_MILLIS, PRIMARY_EXIT_MILLIS, LinearOutSlowInEasing)
        ) { direction * primaryDistance } + fadeIn(
            tween(PRIMARY_ENTER_MILLIS, PRIMARY_EXIT_MILLIS, LinearOutSlowInEasing)
        )
        val exit = slideOutHorizontally(tween(PRIMARY_EXIT_MILLIS, easing = FastOutLinearInEasing)) {
            -direction * primaryDistance
        } + fadeOut(tween(PRIMARY_EXIT_MILLIS, easing = FastOutLinearInEasing))
        return enter togetherWith exit
    }

    val fadeOutMillis = (PAGE_TRANSITION_DURATION_MILLIS * 0.35f).toInt()
    val enter = slideInHorizontally(tween(PAGE_TRANSITION_DURATION_MILLIS, easing = FastOutSlowInEasing)) {
        direction * pageDistance
    } + fadeIn(tween(PAGE_TRANSITION_DURATION_MILLIS - fadeOutMillis, fadeOutMillis, LinearOutSlowInEasing))
    val exit = slideOutHorizontally(tween(PAGE_TRANSITION_DURATION_MILLIS, easing = FastOutSlowInEasing)) {
        -direction * pageDistance
    } + fadeOut(tween(fadeOutMillis, easing = FastOutLinearInEasing))

    return enter togetherWith exit
}
