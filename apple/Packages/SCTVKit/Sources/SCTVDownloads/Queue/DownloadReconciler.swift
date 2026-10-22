import SCTVCore

/// App roots call this after native sessions are recreated, and again on foreground entry.
public struct DownloadReconciler: Sendable {
    private let service: any DownloadService

    public init(service: any DownloadService) { self.service = service }

    public func run() async throws { try await service.reconcile() }
}
