@preconcurrency import AVFoundation
import Foundation
import SCTVCore
import UniformTypeIdentifiers

/// Owns main-queue resource requests and retains at most one bounded chunk per active read.
@MainActor
public final class AssetResourceLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    private static let maximumActive = 4
    private static let maximumPending = 64

    private let reader: MediaResourceReader
    private var source: MediaSource?
    private var assetURL: URL?
    private var pending: [AVAssetResourceLoadingRequest] = []
    private var active: [ObjectIdentifier: Task<Void, Never>] = [:]

    public init(transport: any MediaRangeTransport = URLSessionRangeTransport()) {
        reader = MediaResourceReader(transport: transport)
    }

    /// Creates an asset addressed to this loader rather than the underlying HTTP URL.
    public func makeAsset(source: MediaSource) throws -> AVURLAsset {
        cancelAll()
        guard let url = URL(string: "sctv-media://\(UUID().uuidString)/video.mp4") else {
            throw MediaTransportError.invalidResponse
        }

        self.source = source
        assetURL = url
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }

    /// Cancels the active asset and drains requests still waiting for a read slot.
    public func cancelAll() {
        source = nil
        assetURL = nil
        for task in active.values {
            task.cancel()
        }
        for request in pending where !request.isCancelled {
            request.finishLoading(with: CancellationError())
        }

        // Cancelled active tasks keep their slots until their reads have settled.
        pending.removeAll()
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard request.request.url == assetURL, source != nil else { return false }
        guard pending.count < Self.maximumPending else {
            request.finishLoading(with: MediaTransportError.excessiveBody)
            return true
        }

        pending.append(request)
        startPendingRequests()
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest
    ) {
        pending.removeAll { $0 === request }
        active[ObjectIdentifier(request)]?.cancel()
    }

    private func startPendingRequests() {
        guard let source else { return }
        while active.count < Self.maximumActive, !pending.isEmpty {
            let request = pending.removeFirst()
            guard !request.isCancelled else { continue }
            let identity = ObjectIdentifier(request)
            let reader = reader

            active[identity] = Task { [weak self] in
                defer {
                    self?.active.removeValue(forKey: identity)
                    self?.startPendingRequests()
                }

                await Self.fulfill(request, source: source, reader: reader)
            }
        }
    }

    private static func fulfill(
        _ request: AVAssetResourceLoadingRequest, source: MediaSource, reader: MediaResourceReader
    ) async {
        let dataRequest = request.dataRequest
        let offset = dataRequest.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
        let length: Int?
        if let dataRequest {
            // AVFoundation can have received part of the original request already.
            let consumed = max(0, offset - dataRequest.requestedOffset)
            length =
                dataRequest.requestsAllDataToEndOfResource
                ? nil : max(0, dataRequest.requestedLength - Int(consumed))
        } else {
            length = 0
        }

        do {
            try await reader.read(source: source, offset: offset, length: length) { total, mime in
                request.contentInformationRequest?.contentLength = total
                request.contentInformationRequest?.isByteRangeAccessSupported = true
                request.contentInformationRequest?.contentType =
                    UTType(mimeType: mime)?.identifier ?? UTType.mpeg4Movie.identifier
            } receive: { bytes in
                if !request.isCancelled {
                    dataRequest?.respond(with: bytes)
                }
            }
            if !request.isCancelled {
                request.finishLoading()
            }
        } catch {
            if !request.isCancelled {
                request.finishLoading(with: error)
            }
        }
    }
}
