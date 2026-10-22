import Foundation

public enum DownloadedFile {
    public static func published(_ task: DownloadTask) -> PublishedFile? {
        switch task.state {
        case .completed(let file), .missingFile(let file): file
        default: nil
        }
    }
}
