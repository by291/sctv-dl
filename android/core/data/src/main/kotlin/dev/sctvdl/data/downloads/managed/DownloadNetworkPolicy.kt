package dev.sctvdl.data.downloads.managed

internal data class NetworkStatus(
    val connected: Boolean,
    val wifi: Boolean = false,
    val vpn: Boolean = false,
    val metered: Boolean = false
)

internal object DownloadNetworkPolicy {
    fun allows(wifiOnly: Boolean, network: NetworkStatus): Boolean =
        network.connected && (!wifiOnly || (network.wifi && !network.vpn))
}
