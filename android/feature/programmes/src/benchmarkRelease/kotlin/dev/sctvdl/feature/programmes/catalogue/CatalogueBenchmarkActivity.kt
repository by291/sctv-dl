package dev.sctvdl.feature.programmes.catalogue

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import dev.sctvdl.domain.common.CachedResource
import dev.sctvdl.domain.programme.Programme
import dev.sctvdl.domain.settings.AppSettings
import dev.sctvdl.domain.settings.ThemeMode
import dev.sctvdl.ui.theme.SctvAppTheme

private const val PROGRAMME_COUNT = 100

/** Hosts the production catalogue with stable content for release frame measurements. */
class CatalogueBenchmarkActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val programmes = List(PROGRAMME_COUNT) { index ->
            val number = index + 1
            Programme(
                id = number.toString(),
                name = "Programme $number",
                coverUrl = null,
                serviceOrder = index
            )
        }
        val catalogue = CatalogueUiState(
            resource = CachedResource(programmes),
            featuredId = programmes.first().id
        )
        setContent {
            SctvAppTheme(AppSettings(theme = ThemeMode.Light)) {
                Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                    CatalogueScreen(
                        state = catalogue,
                        favouritesOnly = false,
                        onQuery = {},
                        onSort = {},
                        onRefresh = {},
                        onFavourite = {},
                        onOpen = {},
                        onFilter = {}
                    )
                }
            }
        }
    }
}
