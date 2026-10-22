import Foundation
import Testing

@testable import SCTVCore

struct MediaPolicyTests {
    struct Fixture: Decodable {
        let url: String
        let allowed: Bool
    }

    @Test func matchesSharedFixture() throws {
        let location = try #require(
            Bundle.module.url(
                forResource: "media-policy", withExtension: "json", subdirectory: "Fixtures"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: location))

        for fixture in fixtures {
            let url = try #require(URL(string: fixture.url))
            let accepted = (try? MediaURLPolicy.validate(url)) != nil
            #expect(accepted == fixture.allowed, Comment(rawValue: fixture.url))
        }
    }

    @Test func contentIdentityRejectsNonDecimalIDs() throws {
        #expect(throws: ContentRef.ValidationError.self) {
            try ContentRef(programmeID: "1", dateID: "2026-10-22", contentID: "3")
        }
        let identity = try ContentRef(programmeID: "9007199254740992", dateID: "2", contentID: "3")
        #expect(identity.programmeID == "9007199254740992")
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                ContentRef.self,
                from: Data(#"{"programmeID":"","dateID":"2","contentID":"3"}"#.utf8))
        }
    }
}
