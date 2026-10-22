import Foundation
import SCTVCore

public struct LocalDownloadedFileAccess: DownloadedFileAccess {
    private let repository: any DownloadRepository
    private let publisher: LocalFilePublisher
    public init(repository: any DownloadRepository, publisher: LocalFilePublisher) {
        self.repository = repository
        self.publisher = publisher
    }

    public func open(_ taskID: UUID) async throws -> LocalFileLease {
        guard let task = try await repository.task(taskID),
            let file = DownloadedFile.published(task)
        else { throw DownloadFileError.missingFile }
        let lease = try await publisher.open(file)
        guard let current = try await repository.task(taskID), current.attemptID == task.attemptID,
            DownloadedFile.published(current) == file
        else { throw DownloadFileError.identityChanged }
        return lease
    }
}
