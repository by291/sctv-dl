package dev.sctvdl.data.di

import android.content.IntentSender
import dev.sctvdl.domain.download.DownloadTarget
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/** One-shot platform requests. The repository binds the token to the exact attempt and URI before exposing it. */
@Singleton
class DownloadFileConsentRegistry @Inject constructor() {
    private data class Entry(val uri: String, val sender: IntentSender, val target: DownloadTarget? = null)

    private val requests = ConcurrentHashMap<String, Entry>()

    internal fun register(uri: String, sender: IntentSender): String = UUID.randomUUID().toString().also {
        requests[it] = Entry(uri, sender)
    }

    internal fun bind(token: String, target: DownloadTarget) {
        requests.computeIfPresent(token) { _, entry -> entry.copy(target = target) }
    }

    fun intentSender(token: String): IntentSender? = requests[token]?.sender

    internal fun consume(token: String, target: DownloadTarget): String? = requests.remove(token)?.takeIf {
        it.target ==
            target
    }?.uri
}
