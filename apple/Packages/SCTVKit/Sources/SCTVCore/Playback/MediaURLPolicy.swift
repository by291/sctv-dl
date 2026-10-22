import Foundation

public enum MediaURLPolicy {
    public enum ValidationError: Error { case forbiddenURL }

    public static func validate(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https",
            let host = url.host()?.lowercased(),
            ["fscgc.scgchc.com", "fscgc.sctv-tf.com"].contains(host),
            url.user() == nil, url.password() == nil,
            url.port == nil || url.port == 443,
            url.path(percentEncoded: true).lowercased().hasSuffix(".mp4")
        else { throw ValidationError.forbiddenURL }

        return url
    }
}
