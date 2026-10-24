import Foundation

/// Restricts artwork requests before they reach the image pipeline.
enum ArtworkURLPolicy {
    static func allowed(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", let host = url.host(),
            ["kscgc.sctv.com", "kscgc.scgchc.com", "kscgc.sctv-tf.com"].contains(host),
            url.user() == nil, url.password() == nil, url.port == nil || url.port == 443
        else { return nil }

        return url
    }
}
