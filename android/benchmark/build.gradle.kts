plugins { alias(libs.plugins.android.test) }
android {
    namespace = "dev.sctvdl.benchmark"
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
    buildTypes {
        create("benchmarkRelease") {
            isDebuggable = true
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    targetProjectPath = ":app"
    experimentalProperties["android.experimental.self-instrumenting"] = true
}
androidComponents {
    beforeVariants(selector().all()) { it.enable = it.buildType == "benchmarkRelease" }
}
dependencies {
    implementation(libs.benchmark)
    implementation(libs.android.test.junit)
    implementation(libs.android.test.runner)
    implementation(libs.uiautomator)
}
