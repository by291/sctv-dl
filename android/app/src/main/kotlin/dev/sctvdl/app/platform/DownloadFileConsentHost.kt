package dev.sctvdl.app.platform

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import dev.sctvdl.data.di.DownloadFileConsentRegistry
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

private class ConsentRequestState {
    val lock = Mutex()
    var pending: CompletableDeferred<Boolean>? = null
}

@Composable
internal fun rememberDownloadFileConsentRequester(registry: DownloadFileConsentRegistry): suspend (String) -> Boolean {
    val state = remember { ConsentRequestState() }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) {
        state.pending?.complete(it.resultCode == Activity.RESULT_OK)
    }
    DisposableEffect(state) { onDispose { state.pending?.complete(false) } }
    return remember(registry, launcher) {
        { token: String ->
            state.lock.withLock {
                val sender = registry.intentSender(token)
                if (sender == null) {
                    false
                } else {
                    val result = CompletableDeferred<Boolean>()
                    state.pending = result
                    try {
                        launcher.launch(IntentSenderRequest.Builder(sender).build())
                        result.await()
                    } finally {
                        state.pending = null
                    }
                }
            }
        }
    }
}
