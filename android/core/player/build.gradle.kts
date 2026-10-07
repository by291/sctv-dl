plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.compose)
}
android {
    namespace = "dev.sctvdl.player"
    compileSdk = 37
    defaultConfig {
        minSdk = 29
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    buildFeatures { compose = true }
    lint { abortOnError = true }
}

dependencies {
    implementation(project(":core:domain"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.compose.icons)
    implementation(libs.compose.preview)
    implementation(libs.lifecycle.compose)
    debugImplementation(libs.compose.tooling)
    api(libs.media.exoplayer)
    implementation(libs.media.okhttp)
    implementation(libs.media.session)
    implementation(libs.media.compose)
    implementation(libs.media.ui)
    implementation(libs.okhttp)
    implementation(libs.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.android.test.junit)
    androidTestImplementation(libs.android.test.runner)
    androidTestImplementation(libs.android.test.core)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.activity.compose)
    debugImplementation(libs.compose.test.manifest)
}
