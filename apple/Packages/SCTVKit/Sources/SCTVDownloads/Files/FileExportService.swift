import Foundation
import SCTVCore

public actor FileExportService {
    public init() {}

    public func copy(_ lease: LocalFileLease, to destination: URL, replaceExisting: Bool = false)
        throws
    {
        let access = destination.startAccessingSecurityScopedResource()
        defer { if access { destination.stopAccessingSecurityScopedResource() } }
        try withExtendedLifetime(lease) {
            let manager = FileManager.default
            let temporary = destination.deletingLastPathComponent().appending(
                path: ".sctv-export-\(UUID().uuidString)")
            defer { try? manager.removeItem(at: temporary) }
            try manager.copyItem(at: lease.url, to: temporary)
            if replaceExisting, manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: destination)
            }
        }
    }
}
