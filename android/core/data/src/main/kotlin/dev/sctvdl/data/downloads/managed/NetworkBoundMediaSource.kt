@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)

package dev.sctvdl.data.downloads.managed

import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.okhttp.OkHttpDataSource
import dev.sctvdl.domain.download.DownloadTask
import java.io.IOException

internal class NetworkBoundMediaSource(private val task: DownloadTask, private val access: DownloadNetworkAccess) :
    DataSource {
    private var delegate: DataSource? = null
    private val listeners = mutableListOf<TransferListener>()

    override fun addTransferListener(transferListener: TransferListener) {
        listeners += transferListener
    }

    override fun open(dataSpec: DataSpec): Long {
        val source = OkHttpDataSource.Factory(access.client(task)).createDataSource()
        listeners.forEach(source::addTransferListener)
        delegate = source
        return source.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (!access.permits(task)) throw IOException("Download execution permission withdrawn")
        return requireNotNull(delegate).read(buffer, offset, length)
    }

    override fun getUri() = delegate?.uri

    override fun getResponseHeaders(): Map<String, List<String>> = delegate?.responseHeaders.orEmpty()

    override fun close() {
        delegate?.close()
        delegate = null
    }
}
