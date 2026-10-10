plugins {
    id("sctv.android.compose")
}
android { namespace = "dev.sctvdl.design" }
dependencies {
    implementation(libs.compose.animation)
    implementation(libs.compose.shimmer)
    implementation(libs.lifecycle.compose)
    implementation(libs.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.android.test.junit)
    androidTestImplementation(libs.android.test.runner)
    androidTestImplementation(libs.android.test.core)
}
