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
        let images = ImageCache(costLimit: 64 * 1024 * 1024, countLimit: 128)
        images.entryCostLimit = 0.25
        return ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = images
        }
    }()

    public static func clear() {
        pipeline.cache.removeAll()
        (pipeline.configuration.dataLoader as? DataLoader)?.session.configuration.urlCache?
            .removeAllCachedResponses()
    }

    static func request(url: URL?, width: CGFloat, scale: CGFloat) -> ImageRequest? {
        guard let url = allowed(url), width.isFinite, width > 0, scale.isFinite, scale > 0 else {
            return nil
        }
        // Decode for the rendered size rather than keeping the full source bitmap.
        // Pixel buckets reuse requests across minor layout changes and bound large windows.
        let pixels = min(2048, max(256, ceil(width * scale / 256) * 256))
        var request = ImageRequest(url: url)
        request.thumbnail = .init(maxPixelSize: Float(pixels))
        return request
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
    @Environment(\.displayScale) private var displayScale
    public init(url: URL?) { self.url = url }

    public var body: some View {
        Rectangle().fill(.clear)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let request = ArtworkCache.request(
                        url: url, width: geometry.size.width, scale: displayScale)
                    LazyImage(request: request) { state in
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
                                        .foregroundStyle(
                                            PresentationStyle.accent(scheme).opacity(0.6))
                                }
                        }
                    }
                    .pipeline(ArtworkCache.pipeline)
                    // Nuke's request comparison omits thumbnail options; reload only across buckets.
                    .id(request?.thumbnail)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
