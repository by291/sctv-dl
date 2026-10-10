plugins {
    id("sctv.android.library")
    id("sctv.android.hilt")
    alias(libs.plugins.serialization)
}
android { namespace = "dev.sctvdl.data" }
ksp { arg("room.schemaLocation", "$projectDir/schemas") }
dependencies {
    implementation(project(":core:domain"))
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.datastore)
    implementation(libs.retrofit)
    implementation(libs.okhttp)
    implementation(libs.serialization)
    testImplementation(libs.mockwebserver)
    androidTestImplementation(libs.room.test)
    implementation(libs.coroutines.android)
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.android.test.junit)
    androidTestImplementation(libs.android.test.runner)
    androidTestImplementation(libs.android.test.core)
}
