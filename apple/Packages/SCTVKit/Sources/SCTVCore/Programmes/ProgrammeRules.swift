import Foundation

public enum ProgrammeRules {
    private static let shanghaiOffset = "+08:00"
    private static let titleWhitespace = CharacterSet(
        charactersIn:
            " \t\n\r\u{000B}\u{000C}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    /// Identifies a full broadcast by its exact normalized programme and date title.
    public static func isFullEpisode(title: String, programmeName: String, broadcastDate: String)
        -> Bool
    {
        guard !programmeName.isEmpty, !broadcastDate.isEmpty else { return false }

        let title = String(
            String.UnicodeScalarView(title.unicodeScalars.filter { !titleWhitespace.contains($0) }))
        let date = broadcastDate.replacingOccurrences(of: "-", with: ".")
        return title == "\(programmeName)（\(date)）" || title == "\(programmeName)(\(date))"
    }

    /// Sorts clips by publication time and preserves upstream order for ties and unknown dates.
    public static func sortClips(_ contents: [ProgrammeContent], ascending: Bool)
        -> [ProgrammeContent]
    {
        let datedClips = contents.enumerated().map { index, content in
            (index: index, content: content, time: publicationTime(content.publishedAt))
        }
        let sorted = datedClips.sorted { left, right in
            switch (left.time, right.time) {
            case (.some(let first), .some(let second)) where first != second:
                return ascending ? first < second : first > second
            case (.some, .none): return true
            case (.none, .some): return false
            default: return left.index < right.index
            }
        }

        return sorted.map(\.content)
    }

    /// Parses an upstream timestamp, treating offset-free wall time as Shanghai time.
    public static func publicationTime(_ text: String?) -> Date? {
        guard let text else { return nil }

        var value = text.trimmingCharacters(in: titleWhitespace)
        if let separator = value.range(of: " ") {
            value.replaceSubrange(separator, with: "T")
        }
        let publicationPattern =
            #/
            (?<day>[0-9]{4}-[0-9]{2}-[0-9]{2})
            T(?<minute>[0-9]{2}:[0-9]{2})
            (?::(?<second>[0-9]{2}(?:\.[0-9]+)?))?
            (?<offset>Z|[+-][0-9]{2}:?[0-9]{2})?
            /#
        guard let timestamp = value.wholeMatch(of: publicationPattern)?.output else { return nil }

        let second = timestamp.second ?? "00"
        guard isValidCivilTime(day: timestamp.day, minute: timestamp.minute, second: second) else {
            return nil
        }

        let offset = timestamp.offset ?? Substring(shanghaiOffset)
        let normalized = "\(timestamp.day)T\(timestamp.minute):\(second)\(offset)"
        let formatter = ISO8601DateFormatter()
        if second.contains(".") {
            formatter.formatOptions.insert(.withFractionalSeconds)
        }

        return formatter.date(from: normalized)
    }

    private static func isValidCivilTime(day: Substring, minute: Substring, second: Substring)
        -> Bool
    {
        let dateParts = day.split(separator: "-").compactMap { Int($0) }
        let timeParts = minute.split(separator: ":").compactMap { Int($0) }
        guard let seconds = Int(second.prefix(2)),
            dateParts.count == 3, timeParts.count == 2
        else {
            return false
        }

        // ISO8601DateFormatter normalizes out-of-range dates and times instead of rejecting them.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let civilTime = DateComponents(
            year: dateParts[0], month: dateParts[1], day: dateParts[2],
            hour: timeParts[0], minute: timeParts[1], second: seconds)
        return civilTime.isValidDate(in: calendar)
    }
}
