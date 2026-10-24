import CoreGraphics
import Foundation
import ImageIO
import Nuke
import Testing
import UniformTypeIdentifiers

@testable import SCTVFeatures

@MainActor @Suite(.serialized)
struct ArtworkMemoryTests {
    @Test func artworkRequestsRetainURLRestrictionsAndThumbnailBounds() throws {
        let url = URL(string: "https://kscgc.sctv.com/cover.jpg")!
        for host in ["kscgc.sctv.com", "kscgc.scgchc.com", "kscgc.sctv-tf.com"] {
            let allowed = URL(string: "https://\(host):443/cover.jpg")!
            #expect(ArtworkCache.allowed(allowed) == allowed)
        }
        for address in [
            "http://kscgc.sctv.com/cover.jpg",
            "https://example.com/cover.jpg",
            "https://kscgc.sctv.com:8443/cover.jpg",
            "https://user@kscgc.sctv.com/cover.jpg",
            "https://user:password@kscgc.sctv.com/cover.jpg",
        ] {
            #expect(ArtworkCache.request(url: URL(string: address), width: 136, scale: 3) == nil)
        }
        for width in [CGFloat(0), -1, .infinity, .nan] {
            #expect(ArtworkCache.request(url: url, width: width, scale: 3) == nil)
        }
        for scale in [CGFloat(0), -1, .infinity, .nan] {
            #expect(ArtworkCache.request(url: url, width: 136, scale: scale) == nil)
        }
        let small = try #require(ArtworkCache.request(url: url, width: 1, scale: 1))
        let large = try #require(ArtworkCache.request(url: url, width: 10_000, scale: 3))
        #expect(small.thumbnail == ImageRequest.ThumbnailOptions(maxPixelSize: 256))
        #expect(large.thumbnail == ImageRequest.ThumbnailOptions(maxPixelSize: 2048))
    }

    @Test func compactCoverDecodesBelowSourceResolution() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 3840 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitmap = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, bitmap, nil)
        #expect(CGImageDestinationFinalize(destination))
        let url = URL(string: "https://kscgc.sctv.com/cover.jpg")!
        let request = try #require(ArtworkCache.request(url: url, width: 136, scale: 3))
        let thumbnail = try #require(request.thumbnail?.makeThumbnail(with: data as Data))
        #if os(macOS)
            let decoded = try #require(
                thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #else
            let decoded = try #require(thumbnail.cgImage)
        #endif
        #expect(decoded.width >= 408)
        #expect(decoded.width <= 512)
        #expect(decoded.height <= 288)
        #expect(
            ArtworkCache.request(url: url, width: 137, scale: 3)?.thumbnail == request.thumbnail)
        let expanded = try #require(ArtworkCache.request(url: url, width: 600, scale: 2))
        #expect(expanded.thumbnail != request.thumbnail)
        let expandedImage = try #require(expanded.thumbnail?.makeThumbnail(with: data as Data))
        #if os(macOS)
            let expandedBitmap = try #require(
                expandedImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #else
            let expandedBitmap = try #require(expandedImage.cgImage)
        #endif
        #expect(expandedBitmap.width >= 1200)
        #expect(expandedBitmap.width <= 1280)
        #expect(
            ArtworkCache.request(
                url: URL(string: "https://example.com/cover.jpg"), width: 136, scale: 3) == nil)
    }

    @Test func browsingManyCoversEvictsOlderDecodedImages() throws {
        ArtworkCache.clear()
        defer { ArtworkCache.clear() }
        let context = try #require(
            CGContext(
                data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bitmap = try #require(context.makeImage())
        #if os(macOS)
            let image = PlatformImage(cgImage: bitmap, size: .zero)
        #else
            let image = PlatformImage(cgImage: bitmap)
        #endif
        let requests = (0..<40).map { index in
            ImageRequest(url: URL(string: "https://kscgc.sctv.com/test/\(index).jpg")!)
        }
        for request in requests {
            ArtworkCache.pipeline.cache[request] = ImageContainer(image: image)
        }
        #expect(ArtworkCache.pipeline.cache[requests[0]] == nil)
        #expect(ArtworkCache.pipeline.cache[requests[39]] != nil)
        let cache = try #require(ArtworkCache.pipeline.configuration.imageCache as? ImageCache)
        #expect(cache.totalCost <= 64 * 1024 * 1024)
    }
}
