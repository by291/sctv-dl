pluginManagement {
    includeBuild("build-logic")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "sctv-dl-android"
include(":app", ":core:domain", ":core:data", ":core:design", ":core:player")
include(":baselineprofile", ":benchmark")

include(":core:ui", ":feature:programmes", ":feature:downloads", ":feature:settings", ":feature:player")
