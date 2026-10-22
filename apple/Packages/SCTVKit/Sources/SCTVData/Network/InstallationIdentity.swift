import Foundation

public actor InstallationIdentity {
    private let location: URL
    private var cached: UUID?

    public init(location: URL) { self.location = location }

    public func get() throws -> UUID {
        if let cached { return cached }
        if let text = try? String(contentsOf: location, encoding: .utf8),
            let existing = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            cached = existing
            return existing
        }

        let created = UUID()
        try FileManager.default.createDirectory(
            at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try created.uuidString.write(to: location, atomically: true, encoding: .utf8)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = location
        try file.setResourceValues(values)
        cached = created
        return created
    }
}
