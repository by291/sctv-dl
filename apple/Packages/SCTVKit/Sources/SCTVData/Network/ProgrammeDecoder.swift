import CoreFoundation
import Foundation
import SCTVCore

public enum ProgrammeDecodingError: Error, Equatable, Sendable {
    case invalidJSON
    case invalidEnvelope
    case businessError(String)
    case invalidRecord
    case invalidID
    case invalidDate
}

public enum ProgrammeDecoder {
    private static let maxSafeInteger = 9_007_199_254_740_991
    private static let javascriptWhitespace = CharacterSet(
        charactersIn:
            " \t\n\r\u{000B}\u{000C}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
    )

    public static func decodeCatalogue(_ data: Data) throws -> [Programme] {
        guard let object = try envelope(data) as? [String: Any],
            let rows = object["records"] as? [[String: Any]]
        else {
            throw ProgrammeDecodingError.invalidRecord
        }
        return try rows.map { row in
            Programme(
                id: try id(row["id"]),
                name: row["name"] as? String ?? "未命名栏目",
                cover: url(row["cover"], base: "https://kscgc.sctv.com/")
            )
        }
    }

    public static func decodeDates(_ data: Data) throws -> [BroadcastDate] {
        guard let rows = try envelope(data) as? [[String: Any]] else {
            throw ProgrammeDecodingError.invalidRecord
        }
        var byDate: [String: BroadcastDate] = [:]
        for row in rows {
            guard let date = row["date"] as? String, validDate(date) else {
                throw ProgrammeDecodingError.invalidDate
            }
            byDate[date] = BroadcastDate(id: try id(row["id"]), date: date)
        }
        return byDate.values.sorted { $0.date > $1.date }
    }

    public static func decodeContents(_ data: Data) throws -> [ProgrammeContent] {
        guard let rows = try envelope(data) as? [[String: Any]] else {
            throw ProgrammeDecodingError.invalidRecord
        }
        return try rows.map { row in
            ProgrammeContent(
                id: try id(row["id"]),
                title: row["title"] as? String ?? "未命名节目",
                cover: url(row["cover"], base: "https://kscgc.sctv.com/"),
                video: url(row["video"], base: "https://fscgc.scgchc.com/"),
                smoothVideo: url(row["videoStandard"], base: "https://fscgc.scgchc.com/"),
                publishedAt: row["pubTime"] as? String
            )
        }
    }

    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func envelope(_ data: Data) throws -> Any {
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: data) } catch {
            throw ProgrammeDecodingError.invalidJSON
        }
        guard let envelope = raw as? [String: Any], let status = envelope["rs"] as? NSNumber,
            CFGetTypeID(status) != CFBooleanGetTypeID(), envelope.keys.contains("data")
        else { throw ProgrammeDecodingError.invalidEnvelope }
        guard status.doubleValue == 200 else {
            throw ProgrammeDecodingError.businessError(envelope["error"] as? String ?? "节目服务暂时不可用")
        }
        return envelope["data"]!
    }

    private static func id(_ raw: Any?) throws -> String {
        if let value = raw as? String, validID(value) { return value }
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let value = number.doubleValue
            if value.isFinite, value >= 0, value <= Double(maxSafeInteger),
                value.rounded(.towardZero) == value
            {
                return String(number.int64Value)
            }
        }
        throw ProgrammeDecodingError.invalidID
    }

    private static func validDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard
            let date = calendar.date(
                from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return false }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return components.year == parts[0] && components.month == parts[1]
            && components.day == parts[2]
    }

    private static func url(_ raw: Any?, base: String) -> URL? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: javascriptWhitespace)
        guard !trimmed.isEmpty, let root = URL(string: base),
            let result = URL(string: trimmed, relativeTo: root)?.absoluteURL,
            ["http", "https"].contains(result.scheme?.lowercased() ?? "")
        else { return nil }
        return result
    }
}
