import Foundation

public enum ProgrammeRules {
    private static let titleWhitespace = CharacterSet(
        charactersIn:
            " \t\n\r\u{000B}\u{000C}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    public static func isFullEpisode(title: String, programmeName: String, broadcastDate: String)
        -> Bool
    {
        guard !programmeName.isEmpty, !broadcastDate.isEmpty else { return false }
        let title = String(
            String.UnicodeScalarView(title.unicodeScalars.filter { !titleWhitespace.contains($0) }))
        let date = broadcastDate.replacingOccurrences(of: "-", with: ".")
        return title == "\(programmeName)（\(date)）" || title == "\(programmeName)(\(date))"
    }

    public static func sortClips(_ contents: [ProgrammeContent], ascending: Bool)
        -> [ProgrammeContent]
    {
        contents.enumerated().sorted { left, right in
            let first = publicationTime(left.element.publishedAt)
            let second = publicationTime(right.element.publishedAt)
            switch (first, second) {
            case (.some(let a), .some(let b)) where a != b:
                return ascending ? a < b : a > b
            case (.some, .none): return true
            case (.none, .some): return false
            default: return left.offset < right.offset
            }
        }.map(\.element)
    }

    public static func publicationTime(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        var value = text.trimmingCharacters(in: titleWhitespace)
        if let separator = value.range(of: " ") {
            value.replaceSubrange(separator, with: "T")
        }
        let pattern =
            #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let hasOffset =
            value.range(of: #"(?:Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) != nil
        let normalized = hasOffset ? value : value + "+08:00"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: normalized) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }
}
