plugins { id("sctv.android.compose") }
android { namespace = "dev.sctvdl.ui" }
dependencies {
    implementation(project(":core:domain"))
    implementation(project(":core:design"))
    implementation(libs.compose.animation)
    implementation(libs.lifecycle.compose)
    implementation(libs.coil.compose)
    implementation(libs.coil.network)
    testImplementation(libs.junit)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.test)
    androidTestImplementation(libs.android.test.junit)
    androidTestImplementation(libs.android.test.runner)
    androidTestImplementation(libs.android.test.core)
    debugImplementation(libs.compose.test.manifest)
    androidTestImplementation(libs.activity.compose)
}
