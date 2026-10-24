import CoreGraphics
import Foundation
import Nuke

// The delegate has no mutable state; every redirect is rejected.
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
        ArtworkURLPolicy.allowed(url)
    }
}
