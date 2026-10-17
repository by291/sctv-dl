package dev.sctvdl.data.downloads

import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.sync.Mutex

@Singleton
internal class DownloadTransitions @Inject constructor() {
    val mutex = Mutex()
}
