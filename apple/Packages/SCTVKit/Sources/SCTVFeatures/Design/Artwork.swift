import Foundation
import Nuke
import NukeUI
import SwiftUI

private final class ArtworkRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
public enum ArtworkCache {
    static let pipeline: ImagePipeline = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        let loader = DataLoader(configuration: configuration)
        loader.delegate = ArtworkRedirectPolicy()
        return ImagePipeline { $0.dataLoader = loader }
    }()

    public static func clear() {
        pipeline.cache.removeAll()
        (pipeline.configuration.dataLoader as? DataLoader)?.session.configuration.urlCache?
            .removeAllCachedResponses()
    }

    public static func allowed(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", let host = url.host(),
            ["kscgc.sctv.com", "kscgc.scgchc.com", "kscgc.sctv-tf.com"].contains(host),
            url.user() == nil, url.password() == nil, url.port == nil || url.port == 443
        else { return nil }
        return url
    }
}

public struct Artwork: View {
    let url: URL?
    @Environment(\.colorScheme) private var scheme
    public init(url: URL?) { self.url = url }

    public var body: some View {
        Rectangle().fill(.clear)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                LazyImage(url: ArtworkCache.allowed(url)) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        PresentationStyle.accent(scheme).opacity(0.22),
                                        PresentationStyle.accent(scheme).opacity(0.06),
                                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .overlay {
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 32, weight: .ultraLight))
                                    .foregroundStyle(PresentationStyle.accent(scheme).opacity(0.6))
                            }
                    }
                }
                .pipeline(ArtworkCache.pipeline)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
