@preconcurrency import AVFoundation
import Foundation
import SCTVCore
import UniformTypeIdentifiers

/// The main-queue delegate and its tasks share one owner. Each task retains at most one bounded chunk.
@MainActor
public final class AssetResourceLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    private let reader: MediaResourceReader
    private var source: MediaSource?
    private var assetURL: URL?
    private var pending: [AVAssetResourceLoadingRequest] = []
    private var active: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let maximumActive = 4

    public init(transport: any MediaRangeTransport = URLSessionRangeTransport()) {
        reader = MediaResourceReader(transport: transport)
    }

    public func makeAsset(source: MediaSource) throws -> AVURLAsset {
        cancelAll()
        let url = URL(string: "sctv-media://\(UUID().uuidString)/video.mp4")!
        self.source = source
        assetURL = url
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }

    public func cancelAll() {
        source = nil
        assetURL = nil
        for task in active.values { task.cancel() }
        for request in pending where !request.isCancelled {
            request.finishLoading(with: CancellationError())
        }
        pending.removeAll()
        // Active entries stay until their cancelled tasks finish; replacement loads obey the same cap.
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard request.request.url == assetURL, source != nil else { return false }
        guard pending.count < 64 else {
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
        while active.count < maximumActive, !pending.isEmpty {
            let request = pending.removeFirst()
            guard !request.isCancelled else { continue }
            let identity = ObjectIdentifier(request)
            let reader = reader

            active[identity] = Task { [weak self] in
                defer {
                    self?.active.removeValue(forKey: identity)
                    self?.startPendingRequests()
                }
                do {
                    let dataRequest = request.dataRequest
                    let offset = dataRequest.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
                    let length: Int?
                    if let dataRequest {
                        let consumed = max(0, offset - dataRequest.requestedOffset)
                        length =
                            dataRequest.requestsAllDataToEndOfResource
                            ? nil : max(0, dataRequest.requestedLength - Int(consumed))
                    } else {
                        length = 0
                    }

                    try await reader.read(source: source, offset: offset, length: length) {
                        total, mime in
                        request.contentInformationRequest?.contentLength = total
                        request.contentInformationRequest?.isByteRangeAccessSupported = true
                        request.contentInformationRequest?.contentType =
                            UTType(mimeType: mime)?.identifier ?? UTType.mpeg4Movie.identifier
                    } receive: { data in
                        if !request.isCancelled { dataRequest?.respond(with: data) }
                    }
                    if !request.isCancelled { request.finishLoading() }
                } catch {
                    if !request.isCancelled { request.finishLoading(with: error) }
                }
            }
        }
    }
}
