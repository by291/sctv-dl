plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.android.test) apply false
    alias(libs.plugins.baselineprofile) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.compose) apply false
    alias(libs.plugins.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt) apply false
    alias(libs.plugins.spotless)
}
spotless {
    kotlin {
        target("**/src/**/*.kt")
        ktlint("1.7.1").editorConfigOverride(
            mapOf(
                "ktlint_code_style" to "android_studio",
                "ktlint_function_naming_ignore_when_annotated_with" to "Composable",
                "max_line_length" to "120"
            )
        )
    }
    kotlinGradle {
        target("**/*.gradle.kts")
        targetExclude("**/build/**", ".gradle/**")
        ktlint("1.7.1").editorConfigOverride(mapOf("ktlint_code_style" to "android_studio"))
    }
}

val moduleDependencies = tasks.register("checkModuleDependencies") {
    group = "verification"
    description = "Checks the actual Gradle project dependencies against Android module ownership."
}
gradle.projectsEvaluated {
    val sharedUi = setOf(":core:domain", ":core:design", ":core:ui")
    val allowed = mapOf(
        ":app" to sharedUi + setOf(
            ":core:data",
            ":core:player",
            ":baselineprofile",
            ":feature:programmes",
            ":feature:downloads",
            ":feature:settings",
            ":feature:player"
        ),
        ":core:domain" to emptySet(),
        ":core:data" to setOf(":core:domain"),
        ":core:design" to emptySet(),
        ":core:ui" to setOf(":core:domain", ":core:design"),
        ":core:player" to setOf(":core:domain"),
        ":feature:programmes" to sharedUi,
        ":feature:downloads" to sharedUi,
        ":feature:settings" to sharedUi,
        ":feature:player" to sharedUi + ":core:player",
        ":baselineprofile" to setOf(":app"),
        ":benchmark" to setOf(":app")
    )
    val edges = allowed.keys.associateWith { path ->
        project(path).configurations.flatMap { configuration ->
            configuration.dependencies.withType<org.gradle.api.artifacts.ProjectDependency>().map { it.path }
        }.toSet()
    }
    moduleDependencies.configure {
        inputs.property("moduleDependencies", edges)
        doLast {
            val forbidden = edges.flatMap { (owner, targets) ->
                (targets - owner - allowed.getValue(owner)).map { "$owner -> $it" }
            }
            check(forbidden.isEmpty()) { "Forbidden module dependencies:\n${forbidden.joinToString("\n")}" }
        }
    }
    tasks.named("check") {
        group = "verification"
        dependsOn(moduleDependencies)
        dependsOn(subprojects.mapNotNull { it.tasks.findByName("check") })
    }
}
