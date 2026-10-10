package dev.sctvdl.app.navigation

internal class AppNavigator(val open: (AppRoute) -> Unit, val back: () -> Unit)
