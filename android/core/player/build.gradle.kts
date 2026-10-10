plugins {
    id("sctv.android.compose")
}
android { namespace = "dev.sctvdl.player" }
dependencies {
    implementation(project(":core:domain"))
    implementation(libs.lifecycle.compose)
    api(libs.media.exoplayer)
    implementation(libs.media.okhttp)
    implementation(libs.media.session)
    implementation(libs.media.compose)
    implementation(libs.media.compose.material3)
    implementation(libs.media.ui)
    implementation(libs.okhttp)
    implementation(libs.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.android.test.junit)
    androidTestImplementation(libs.android.test.runner)
    androidTestImplementation(libs.android.test.core)
    androidTestImplementation(libs.uiautomator)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.activity.compose)
    debugImplementation(libs.compose.test.manifest)
}
