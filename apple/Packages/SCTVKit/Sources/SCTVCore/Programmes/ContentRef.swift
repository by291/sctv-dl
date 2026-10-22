import Foundation

public struct ContentRef: Hashable, Codable, Sendable {
    public enum ValidationError: Error { case invalidID }

    public let programmeID: String
    public let dateID: String
    public let contentID: String

    public init(programmeID: String, dateID: String, contentID: String) throws {
        guard
            [programmeID, dateID, contentID].allSatisfy({
                !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
            })
        else { throw ValidationError.invalidID }

        self.programmeID = programmeID
        self.dateID = dateID
        self.contentID = contentID
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            programmeID: values.decode(String.self, forKey: .programmeID),
            dateID: values.decode(String.self, forKey: .dateID),
            contentID: values.decode(String.self, forKey: .contentID)
        )
    }
}
