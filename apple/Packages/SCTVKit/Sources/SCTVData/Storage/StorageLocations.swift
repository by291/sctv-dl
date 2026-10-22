import Foundation

public struct StorageLocations: Sendable {
    public let userDatabase: URL
    public let runtimeDatabase: URL
    public let installationIdentity: URL

    public init(userDatabase: URL, runtimeDatabase: URL, installationIdentity: URL) {
        self.userDatabase = userDatabase
        self.runtimeDatabase = runtimeDatabase
        self.installationIdentity = installationIdentity
    }

    public init(root: URL) {
        self.init(
            userDatabase: root.appending(path: "user.sqlite"),
            runtimeDatabase: root.appending(path: "Runtime/runtime.sqlite"),
            installationIdentity: root.appending(path: "Runtime/installation-id")
        )
    }
}
