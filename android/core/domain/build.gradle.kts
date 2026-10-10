plugins {
    alias(libs.plugins.kotlin.jvm)
    `java-test-fixtures`
}
kotlin { jvmToolchain(21) }
dependencies {
    implementation(libs.coroutines)
    testFixturesImplementation(libs.junit)
    testFixturesImplementation(libs.coroutines.test)
    testFixturesImplementation(libs.coroutines)
    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
}
