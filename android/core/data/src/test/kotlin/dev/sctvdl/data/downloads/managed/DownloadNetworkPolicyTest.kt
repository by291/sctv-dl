package dev.sctvdl.data.downloads.managed

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadNetworkPolicyTest {
    @Test fun wifiPolicyUsesTransportAndNeverBypassesVpn() {
        assertFalse(DownloadNetworkPolicy.allows(true, NetworkStatus(connected = true, wifi = false)))
        assertTrue(DownloadNetworkPolicy.allows(true, NetworkStatus(connected = true, wifi = true, metered = true)))
        assertFalse(DownloadNetworkPolicy.allows(true, NetworkStatus(connected = true, wifi = true, vpn = true)))
        assertTrue(DownloadNetworkPolicy.allows(false, NetworkStatus(connected = true, wifi = false, vpn = true)))
        assertFalse(DownloadNetworkPolicy.allows(false, NetworkStatus(connected = false)))
    }
}
