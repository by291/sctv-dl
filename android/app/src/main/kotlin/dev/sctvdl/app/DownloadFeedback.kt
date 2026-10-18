package dev.sctvdl.app

import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect

@Composable
internal fun DownloadFeedback(
    message: AppMessage?,
    snackbar: SnackbarHostState,
    onConsumed: (Long) -> Unit,
    onOpenDownloads: () -> Unit
) {
    LaunchedEffect(message) {
        message?.let {
            val result = snackbar.showSnackbar(
                it.text,
                actionLabel = "查看下载",
                duration = SnackbarDuration.Short
            )
            onConsumed(it.id)
            if (result == SnackbarResult.ActionPerformed) onOpenDownloads()
        }
    }
}
