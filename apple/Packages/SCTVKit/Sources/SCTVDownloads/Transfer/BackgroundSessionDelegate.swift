import Foundation
import SCTVCore

/// URLSession callbacks arrive on a serial delegate queue. This queue preserves their order
/// across the hop into the actor so a drain marker cannot overtake an adopted file.
private final class OrderedCallbacks: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [TransferEvent] = []
    private var pumping = false
    weak var driver: BackgroundSessionDriver?

    func append(_ event: TransferEvent) {
        lock.lock()
        pending.append(event)
        let start = !pumping
        if start { pumping = true }
        lock.unlock()
        if start { Task { await pump() } }
    }

    private func pump() async {
        while true {
            let event = lock.withLock { () -> TransferEvent? in
                guard !pending.isEmpty else {
                    pumping = false
                    return nil
                }
                return pending.removeFirst()
            }
            guard let event else { return }
            await driver?.emit(event)
        }
    }
}

final class BackgroundSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let identifier: String
    private let staging: DownloadStagingStore
    private let resumes: ResumeDataStore
    private let failures: TerminalFailureStore
    private let callbacks = OrderedCallbacks()
    private let lock = NSLock()
    private var finishedTasks: Set<Int> = []
    private var suppressedTasks: Set<Int> = []

    init(
        identifier: String, staging: DownloadStagingStore, resumes: ResumeDataStore,
        failures: TerminalFailureStore
    ) {
        self.identifier = identifier
        self.staging = staging
        self.resumes = resumes
        self.failures = failures
    }

    func attach(_ driver: BackgroundSessionDriver) { callbacks.driver = driver }

    func suppress(_ nativeTask: Int) {
        lock.lock()
        suppressedTasks.insert(nativeTask)
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let correlation = TransferCorrelation.decode(downloadTask.taskDescription) else {
            return
        }
        callbacks.append(
            .progress(
                taskID: correlation.taskID, attemptID: correlation.attemptID,
                nativeID: nativeID(downloadTask), received: totalBytesWritten,
                total: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64
    ) {
        guard let correlation = TransferCorrelation.decode(downloadTask.taskDescription) else {
            return
        }
        callbacks.append(
            .progress(
                taskID: correlation.taskID, attemptID: correlation.attemptID,
                nativeID: nativeID(downloadTask), received: fileOffset,
                total: expectedTotalBytes > 0 ? expectedTotalBytes : nil))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let correlation = TransferCorrelation.decode(downloadTask.taskDescription) else {
            return
        }
        let id = nativeID(downloadTask)

        lock.lock()
        finishedTasks.insert(downloadTask.taskIdentifier)
        lock.unlock()

        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        queue(
            adoptCallbackFile(
                at: location, taskID: correlation.taskID, attemptID: correlation.attemptID,
                nativeID: id, statusCode: statusCode))
    }

    func adoptCallbackFile(
        at location: URL, taskID: UUID, attemptID: UUID,
        nativeID: NativeTransferID, statusCode: Int?
    ) -> TransferEvent {
        guard let statusCode else {
            return .failed(
                taskID: taskID, attemptID: attemptID, nativeID: nativeID,
                reason: "Transfer returned no HTTP response", resume: nil)
        }
        guard (200..<300).contains(statusCode) else {
            return .failed(
                taskID: taskID, attemptID: attemptID, nativeID: nativeID,
                reason: "HTTP \(statusCode)", resume: nil)
        }
        do {
            // The system may delete location as soon as this callback returns.
            let staged = try staging.adoptTemporaryFile(
                at: location, taskID: taskID, attemptID: attemptID)
            return .staged(staged, nativeID: nativeID)
        } catch {
            return .failed(
                taskID: taskID, attemptID: attemptID, nativeID: nativeID,
                reason: error.localizedDescription, resume: nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        guard let correlation = TransferCorrelation.decode(task.taskDescription) else { return }
        let taskNumber = task.taskIdentifier
        lock.lock()
        let finished = finishedTasks.remove(taskNumber) != nil
        let suppressed = suppressedTasks.remove(taskNumber) != nil
        lock.unlock()
        guard !finished, !suppressed else { return }

        var reference: ResumeReference?
        if let error = error as NSError?,
            let data = error.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        {
            reference = try? resumes.save(
                data, taskID: correlation.taskID, attemptID: correlation.attemptID)
        }
        let reason: String
        reason = error?.localizedDescription ?? "Transfer ended without a file"
        queue(
            .failed(
                taskID: correlation.taskID, attemptID: correlation.attemptID,
                nativeID: nativeID(task), reason: reason, resume: reference))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        callbacks.append(.drain(identifier: identifier, token: UUID()))
    }

    private func queue(_ event: TransferEvent) {
        // The durable receipt closes the callback-before-native-ID-commit window.
        try? failures.save(event)
        callbacks.append(event)
    }

    private func nativeID(_ task: URLSessionTask) -> NativeTransferID {
        NativeTransferID(session: identifier, task: task.taskIdentifier)
    }
}
