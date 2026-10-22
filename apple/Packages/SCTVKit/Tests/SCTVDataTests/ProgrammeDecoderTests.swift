import Foundation
import Testing

@testable import SCTVData

struct ProgrammeDecoderTests {
    @Test func sharedFixturesPreserveLargeStringIDsAndURLWhitespace() throws {
        let file = try #require(
            Bundle.module.url(
                forResource: "programmes", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        for fixture in cases {
            let raw = try JSONSerialization.data(withJSONObject: [
                "rs": 200, "data": fixture["raw"]!,
            ])
            let expected = try #require(fixture["expected"] as? [[String: Any]])
            let decoded = try ProgrammeDecoder.decodeContents(raw)
            #expect(decoded.map(\.id) == expected.compactMap { $0["id"] as? String })
            #expect(
                decoded.map { $0.video?.absoluteString } == expected.map { $0["video"] as? String })
            #expect(
                decoded.map { $0.smoothVideo?.absoluteString }
                    == expected.map { $0["smoothVideo"] as? String })
        }
    }

    @Test func rejectsUnsafeNumericIDButAcceptsSameString() throws {
        let numeric = Data(#"{"rs":200,"data":[{"id":9007199254740992,"title":"News"}]}"#.utf8)
        #expect(throws: (any Error).self) { try ProgrammeDecoder.decodeContents(numeric) }
        let string = Data(#"{"rs":200,"data":[{"id":"9007199254740992","title":"News"}]}"#.utf8)
        #expect(try ProgrammeDecoder.decodeContents(string).first?.id == "9007199254740992")
    }

    @Test func datesKeepLastRecordAndNewestFirst() throws {
        let body = Data(
            #"{"rs":200,"data":[{"id":1,"date":"2026-10-05"},{"id":2,"date":"2026-10-06"},{"id":3,"date":"2026-10-05"}]}"#
                .utf8)
        #expect(try ProgrammeDecoder.decodeDates(body).map(\.id) == ["2", "3"])
    }

    @Test func fractionalEnvelopeStatusDoesNotMasqueradeAsSuccess() {
        let body = Data(#"{"rs":200.5,"data":[]}"#.utf8)
        #expect(throws: ProgrammeDecodingError.self) { try ProgrammeDecoder.decodeContents(body) }
    }
}
