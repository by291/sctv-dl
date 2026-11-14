import Foundation

/// Stable failure codes stored in a task's reason string for localized presentation.
public enum DownloadIssueCode: String, Sendable, LocalizedError {
    case unsafePath
    case missingFile
    case accessDenied
    case identityChanged
    case emptyFile
    case invalidMedia
    case missingCallbackFile
    case stagedPathOccupied
    case unknownSession
    case invalidResume
    case invalidSource

    public var errorDescription: String? {
        switch self {
        case .unsafePath: "The download file path is invalid."
        case .missingFile: "The downloaded file is no longer present."
        case .accessDenied: "The download directory is not accessible."
        case .identityChanged: "The downloaded file has been replaced."
        case .emptyFile: "The downloaded file is empty."
        case .invalidMedia: "The downloaded bytes are not playable media."
        case .missingCallbackFile: "The temporary download file is unavailable."
        case .stagedPathOccupied: "The download staging path is occupied."
        case .unknownSession: "The background session is unavailable."
        case .invalidResume: "The resume data cannot be loaded."
        case .invalidSource: "The download source URL is invalid."
        }
    }
}
