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
