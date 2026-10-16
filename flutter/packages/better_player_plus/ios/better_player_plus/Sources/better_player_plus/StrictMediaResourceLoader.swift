import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Gives AVPlayer a streaming, cancellable MP4 transport whose redirect policy is
/// controlled by the application. No full-file memory cache or local relay exists.
final class StrictMediaResourceLoader: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private struct Pending {
        let loading: AVAssetResourceLoadingRequest
        let start: Int64
        let end: Int64
        var received: Int64 = 0
        var total: Int64?
    }

    private let originalURL: URL
    private let headers: [AnyHashable: Any]
    // All mutable state and URLSession creation are confined to this queue.
    private let queue = DispatchQueue(label: "dev.sctvdl.player.media")
    private var pending: [Int: Pending] = [:]
    private var invalidated = false
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        // A progressing video does not have a metadata-sized whole-operation deadline.
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(url: URL, headers: [AnyHashable: Any]) {
        originalURL = url
        self.headers = headers
    }

    func asset() -> AVURLAsset {
        var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)!
        components.scheme = "sctv-media"
        let asset = AVURLAsset(url: components.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    func invalidate() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !invalidated else { return }
            invalidated = true
            for item in pending.values { item.loading.finishLoading(with: URLError(.cancelled)) }
            pending.removeAll()
            session.invalidateAndCancel()
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard !invalidated else { return false }
        start(loadingRequest)
        return true
    }

    private func start(_ loading: AVAssetResourceLoadingRequest) {
        let request = loading.dataRequest
        let start = request.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
        let remaining = request.map { max(0, $0.requestedOffset + Int64($0.requestedLength) - start) } ?? 2
        guard remaining > 0 || request?.requestsAllDataToEndOfResource == true else { loading.finishLoading(); return }
        // Bound each response so seeking never leaves a whole-file read in flight.
        let count = min(request?.requestsAllDataToEndOfResource == true ? 1_048_576 : remaining, 1_048_576)
        let end = start + max(1, count) - 1
        var network = URLRequest(url: originalURL)
        for (name, value) in headers {
            if let name = name as? String, let value = value as? String { network.setValue(value, forHTTPHeaderField: name) }
        }
        network.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        network.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.dataTask(with: network)
        pending[task.taskIdentifier] = Pending(loading: loading, start: start, end: end)
        task.resume()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        let ids = pending.filter { $0.value.loading === loadingRequest }.map(\.key)
        for id in ids { pending.removeValue(forKey: id) }
        session.getAllTasks { tasks in for task in tasks where ids.contains(task.taskIdentifier) { task.cancel() } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        queue.async { [weak self] in
            guard let self = self else { return }
            fail(task.taskIdentifier, URLError(.httpTooManyRedirects))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard var item = pending[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
            guard (200...299).contains(http.statusCode), item.start == 0 || http.statusCode == 206 else {
                fail(dataTask.taskIdentifier, URLError(.badServerResponse)); completionHandler(.cancel); return
            }
            let range = http.value(forHTTPHeaderField: "Content-Range")
            let total = range?.split(separator: "/").last.flatMap { Int64($0) } ?? response.expectedContentLength
            if http.statusCode == 206, let range = range {
                let expected = "bytes \(item.start)-"
                guard range.hasPrefix(expected) else { fail(dataTask.taskIdentifier, URLError(.badServerResponse)); completionHandler(.cancel); return }
            }
            item.total = total >= 0 ? total : nil
            pending[dataTask.taskIdentifier] = item
            if let info = item.loading.contentInformationRequest {
                info.contentType = UTType(mimeType: response.mimeType ?? "video/mp4")?.identifier ?? UTType.mpeg4Movie.identifier
                info.contentLength = max(0, total)
                info.isByteRangeAccessSupported = http.statusCode == 206 || http.value(forHTTPHeaderField: "Accept-Ranges") == "bytes"
            }
            if item.loading.dataRequest == nil {
                pending.removeValue(forKey: dataTask.taskIdentifier)
                item.loading.finishLoading(); completionHandler(.cancel)
            } else { completionHandler(.allow) }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard var item = pending[dataTask.taskIdentifier] else { return }
            let available = max(0, item.end - item.start + 1 - item.received)
            let delivered = data.prefix(Int(min(Int64(data.count), available)))
            item.loading.dataRequest?.respond(with: delivered)
            item.received += Int64(delivered.count)
            pending[dataTask.taskIdentifier] = item
            if item.received >= item.end - item.start + 1 {
                pending.removeValue(forKey: dataTask.taskIdentifier)
                dataTask.cancel()
                if let total = item.total, item.start + item.received >= total { item.loading.finishLoading() }
                else { continueOrFinish(item.loading) }
            }
        }
    }

    private func continueOrFinish(_ loading: AVAssetResourceLoadingRequest) {
        guard let request = loading.dataRequest, !loading.isCancelled else { return }
        if request.currentOffset < request.requestedOffset + Int64(request.requestedLength) || request.requestsAllDataToEndOfResource {
            start(loading)
        } else { loading.finishLoading() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let item = pending.removeValue(forKey: task.taskIdentifier) else { return }
            if let error = error { item.loading.finishLoading(with: error) }
            else { item.loading.finishLoading() }
        }
    }

    private func fail(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.loading.finishLoading(with: error)
    }
}
