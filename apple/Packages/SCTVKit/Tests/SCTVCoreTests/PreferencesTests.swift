import Foundation
import Testing

@testable import SCTVCore

struct PreferencesTests {
    @Test func missingOrInvalidSavedFieldsRecoverIndividually() throws {
        let saved = Data(#"{"appearance":"dark","playbackQuality":"invalid"}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: saved)
        #expect(decoded.appearance == .dark)
        #expect(decoded.playbackQuality == .standard)
        #expect(!decoded.allowCellularDownloads)
    }
}
