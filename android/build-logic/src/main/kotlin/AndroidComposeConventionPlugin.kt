import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.artifacts.VersionCatalogsExtension
import org.gradle.kotlin.dsl.configure
import org.gradle.kotlin.dsl.getByType

/** Layers Compose support and shared UI dependencies on top of [AndroidLibraryConventionPlugin]. */
class AndroidComposeConventionPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        with(target) {
            pluginManager.apply("sctv.android.library")
            pluginManager.apply("org.jetbrains.kotlin.plugin.compose")

            extensions.configure<LibraryExtension> {
                buildFeatures.compose = true
            }

            val libs = extensions.getByType<VersionCatalogsExtension>().named("libs")

            // The shared BOM keeps Compose artifact versions aligned across modules.
            dependencies.add("implementation", dependencies.platform(libs.findLibrary("compose-bom").get()))
            listOf("compose-ui", "compose-material3", "compose-icons", "compose-preview").forEach {
                dependencies.add("implementation", libs.findLibrary(it).get())
            }

            // Runtime inspection tooling belongs in debug builds to avoid adding it to release dependencies.
            dependencies.add("debugImplementation", libs.findLibrary("compose-tooling").get())
        }
    }
}
