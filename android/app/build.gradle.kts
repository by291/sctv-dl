plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.baselineprofile)
    alias(libs.plugins.compose)
    alias(libs.plugins.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

fun gitOutput(vararg arguments: String): String = providers.exec {
    workingDir(rootProject.projectDir)
    commandLine("git", *arguments)
}.standardOutput.asText.get().trim()

// Commit counts are reproducible version codes only when the complete history is available.
check(gitOutput("rev-parse", "--is-shallow-repository") == "false") {
    "Android version codes require full Git history. Run git fetch --unshallow before building."
}
val gitCommitCount = gitOutput("rev-list", "--count", "HEAD").toInt()
val gitShortCommit = gitOutput("rev-parse", "--short=7", "HEAD")

android {
    namespace = "dev.sctvdl.app"
    compileSdk = 37
    defaultConfig {
        applicationId = "dev.sctvdl.app"
        minSdk = 29
        targetSdk = 37
        versionCode = gitCommitCount
        versionName = "0.1.1-$gitShortCommit"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    buildFeatures { compose = true }
    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    lint { abortOnError = true }
}
dependencies {
    implementation(project(":core:domain"))
    implementation(project(":core:data"))
    implementation(project(":core:design"))
    implementation(project(":core:ui"))
    implementation(project(":feature:programmes"))
    implementation(project(":feature:downloads"))
    implementation(project(":feature:settings"))
    implementation(project(":feature:player"))
    implementation(project(":core:player"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.animation)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.compose.preview)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.compose)
    implementation(libs.lifecycle.viewmodel)
    implementation(libs.lifecycle.navigation)
    implementation(libs.navigation.ui)
    implementation(libs.navigation.runtime)
    implementation(libs.hilt.android)
    implementation(libs.hilt.compose)
    ksp(libs.hilt.compiler)
    implementation(libs.serialization)
    implementation(libs.coroutines.android)
    implementation(libs.coil.compose)
    implementation(libs.coil.network)
    implementation(libs.okhttp)
    implementation(libs.profileinstaller)
    baselineProfile(project(":baselineprofile"))
    testImplementation(testFixtures(project(":core:domain")))
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.test)
    androidTestImplementation(libs.android.test.junit)
    androidTestImplementation(libs.android.test.runner)
    androidTestImplementation(libs.android.test.core)
    androidTestImplementation(libs.uiautomator)
    debugImplementation(libs.compose.test.manifest)
    debugImplementation(libs.compose.tooling)
}
baselineProfile {
    mergeIntoMain = true
    automaticGenerationDuringBuild = false
}
