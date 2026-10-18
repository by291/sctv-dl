package dev.sctvdl.feature.programmes

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.feature.programmes.catalogue.components.ProgrammeCard
import dev.sctvdl.ui.theme.SctvAppTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ProgrammeFavouriteTargetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun tapsOutsideTheVisibleFavouriteButtonOpenTheProgramme() {
        var opens = 0
        var favourites = 0
        compose.setContent {
            SctvAppTheme(AppSettings()) {
                Box(Modifier.padding(24.dp).width(220.dp)) {
                    ProgrammeCard(
                        Programme("fixture", "Fixture", null, 0),
                        false,
                        { opens++ },
                        { favourites++ }
                    )
                }
            }
        }
        val favourite = compose.onNodeWithContentDescription("收藏Fixture")
        val bounds = favourite.getBoundsInRoot()
        compose.onRoot().performTouchInput {
            click(Offset((bounds.right + 2.dp).toPx(), ((bounds.top + bounds.bottom) / 2).toPx()))
        }
        compose.runOnIdle {
            assertEquals("The cover outside the visible button must open playback browsing", 1, opens)
            assertEquals(0, favourites)
        }

        favourite.performClick()
        compose.runOnIdle {
            assertEquals(1, opens)
            assertEquals(1, favourites)
        }
    }
}
