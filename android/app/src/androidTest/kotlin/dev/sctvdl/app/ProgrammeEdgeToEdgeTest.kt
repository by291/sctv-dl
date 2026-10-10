package dev.sctvdl.app

import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import dev.sctvdl.app.navigation.AppNavigationShell
import dev.sctvdl.app.navigation.AppRoute
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProgrammeEdgeToEdgeTest {
    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test fun catalogueFollowsNavigationPositionWhileArchiveAlwaysReachesTheWindowBottom() {
        var windowBottom = 0f
        val destinationBottoms = mutableMapOf<AppRoute, Float>()
        val destinationPadding = mutableMapOf<AppRoute, Dp>()
        val archive = AppRoute.Archive("one")

        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.enableEdgeToEdge()
                activity.setContent {
                    SctvAppTheme(AppSettings()) {
                        Box(
                            Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }.onGloballyPositioned {
                                windowBottom =
                                    it.boundsInWindow().bottom
                            }
                        ) {
                            AppNavigationShell { route, navigator, bottomPadding ->
                                destinationPadding[route] = bottomPadding
                                Box(
                                    Modifier.fillMaxSize().onGloballyPositioned {
                                        destinationBottoms[route] = it.boundsInWindow().bottom
                                    }
                                ) {
                                    Button(
                                        onClick = {
                                            navigator.open(if (route == archive) AppRoute.Downloads else archive)
                                        },
                                        modifier = Modifier.align(Alignment.TopCenter)
                                    ) {
                                        Text(
                                            when (route) {
                                                archive -> "Archive viewport"
                                                AppRoute.Downloads -> "Downloads viewport"
                                                else -> "Open archive"
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            val open = requireNotNull(device.wait(Until.findObject(By.text("Open archive")), 5_000))
            device.waitForIdle()
            val catalogueTab = requireNotNull(device.findObject(By.res("tab-Catalogue"))).visibleBounds
            val settingsTab = requireNotNull(device.findObject(By.res("tab-Settings"))).visibleBounds
            val sideNavigation = catalogueTab.centerX() == settingsTab.centerX()
            scenario.onActivity {
                assertTrue("The fixture must have a measured window", windowBottom > 0f)
                if (sideNavigation) {
                    assertEquals(
                        "The library must scroll beneath system navigation beside a rail",
                        windowBottom,
                        requireNotNull(destinationBottoms[AppRoute.Catalogue]),
                        1f
                    )
                    assertTrue(requireNotNull(destinationPadding[AppRoute.Catalogue]) > 0.dp)
                } else {
                    assertTrue(
                        "The library must remain above bottom navigation",
                        requireNotNull(destinationBottoms[AppRoute.Catalogue]) < windowBottom
                    )
                    assertEquals(0.dp, destinationPadding[AppRoute.Catalogue])
                }
            }

            open.click()
            requireNotNull(device.wait(Until.findObject(By.text("Archive viewport")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                assertEquals(
                    "The archive must scroll beneath gesture navigation",
                    windowBottom,
                    requireNotNull(destinationBottoms[archive]),
                    1f
                )
                assertTrue(
                    "The archive must reserve gesture spacing inside its list",
                    requireNotNull(destinationPadding[archive]) > 0.dp
                )
            }

            requireNotNull(device.findObject(By.text("Archive viewport"))).click()
            requireNotNull(device.wait(Until.findObject(By.text("Downloads viewport")), 5_000))
            device.waitForIdle()
            scenario.onActivity {
                assertTrue(
                    "Other destinations must keep their content above navigation",
                    requireNotNull(destinationBottoms[AppRoute.Downloads]) < windowBottom
                )
            }
        }
    }
}
