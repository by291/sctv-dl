import Foundation
import SCTVCore

enum SnapshotComparison {
    static func hasMeaningfulChange(_ first: ProgrammeItems, _ second: ProgrammeItems) -> Bool {
        switch (first, second) {
        case (.catalogue(let a), .catalogue(let b)):
            return !sameElements(a, b) {
                $0.id == $1.id && normalize($0.name) == normalize($1.name)
                    && $0.cover == $1.cover
            }
        case (.dates(let a), .dates(let b)):
            return !sameElements(a, b) {
                $0.id == $1.id && normalize($0.date) == normalize($1.date)
            }
        case (.contents(let a), .contents(let b)):
            return !sameElements(a, b) {
                $0.id == $1.id && normalize($0.title) == normalize($1.title)
                    && $0.cover == $1.cover && $0.video == $1.video
                    && $0.smoothVideo == $1.smoothVideo
                    && samePublicationTime($0.publishedAt, $1.publishedAt)
            }
        default:
            return true
        }
    }

    private static func sameElements<T>(_ first: [T], _ second: [T], by equal: (T, T) -> Bool)
        -> Bool
    {
        first.count == second.count && zip(first, second).allSatisfy(equal)
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func samePublicationTime(_ first: String?, _ second: String?) -> Bool {
        if let left = ProgrammeRules.publicationTime(first),
            let right = ProgrammeRules.publicationTime(second)
        {
            return left == right
        }
        return first.map(normalize) == second.map(normalize)
    }
}
