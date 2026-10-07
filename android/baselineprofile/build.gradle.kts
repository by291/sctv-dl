plugins {
    alias(libs.plugins.android.test)
    alias(libs.plugins.baselineprofile)
}
android {
    namespace = "dev.sctvdl.baselineprofile"
    compileSdk = 37
    defaultConfig {
        minSdk = 29
        targetSdk = 37
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    targetProjectPath = ":app"
    experimentalProperties["android.experimental.self-instrumenting"] = true
}
baselineProfile { useConnectedDevices = true }
dependencies {
    implementation(libs.benchmark)
    implementation(libs.android.test.junit)
    implementation(libs.android.test.runner)
    implementation(libs.uiautomator)
}
