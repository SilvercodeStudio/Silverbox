import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// One top-level record of a LaunchBox XML file: the element name (`Game`,
/// `Platform`, `Playlist`, …) and its child elements as text fields.
nonisolated public struct LaunchBoxRecord: Sendable {
    public var element: String
    public var fields: [String: String]

    public init(element: String, fields: [String: String]) {
        self.element = element
        self.fields = fields
    }

    public var reader: FieldReader { FieldReader(fields: fields) }
}

nonisolated public enum LaunchBoxXMLError: Error, Sendable {
    case cannotOpen(URL)
    case parseFailed(URL, String)
}

/// A streaming parser for LaunchBox's flat XML layout:
///
/// ```xml
/// <LaunchBox>
///   <Game><Title>…</Title>…</Game>
///   <AlternateName>…</AlternateName>
/// </LaunchBox>
/// ```
nonisolated public enum LaunchBoxXMLParser {
    /// Parses `url`, calling `onRecord` for each top-level record in order.
    public static func parse(url: URL, onRecord: @escaping (LaunchBoxRecord) throws -> Void) throws {
        guard let parser = XMLParser(contentsOf: url) else { throw LaunchBoxXMLError.cannotOpen(url) }
        let delegate = RecordDelegate(onRecord: onRecord)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let finished = parser.parse()
        if let error = delegate.thrownError { throw error }
        if !finished, !delegate.aborted {
            let message = parser.parserError?.localizedDescription ?? "unknown parser error"
            throw LaunchBoxXMLError.parseFailed(url, message)
        }
    }

    /// Parses `url` and returns every record. Prefer ``parse(url:onRecord:)``
    /// for the large platform files.
    public static func parseAll(url: URL) throws -> [LaunchBoxRecord] {
        var records: [LaunchBoxRecord] = []
        try parse(url: url) { records.append($0) }
        return records
    }

    /// Parses XML held in memory. Used by tests.
    public static func parse(data: Data, onRecord: @escaping (LaunchBoxRecord) throws -> Void) throws {
        let parser = XMLParser(data: data)
        let delegate = RecordDelegate(onRecord: onRecord)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let finished = parser.parse()
        if let error = delegate.thrownError { throw error }
        if !finished, !delegate.aborted {
            let message = parser.parserError?.localizedDescription ?? "unknown parser error"
            throw LaunchBoxXMLError.parseFailed(URL(fileURLWithPath: "/dev/null"), message)
        }
    }
}

nonisolated private final class RecordDelegate: NSObject, XMLParserDelegate {
    private let onRecord: (LaunchBoxRecord) throws -> Void
    private var depth = 0
    private var currentElement: String?
    private var fields: [String: String] = [:]
    private var currentField: String?
    private var text = ""
    private(set) var thrownError: Error?
    private(set) var aborted = false

    init(onRecord: @escaping (LaunchBoxRecord) throws -> Void) {
        self.onRecord = onRecord
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        switch depth {
        case 2:
            currentElement = elementName
            fields = [:]
        case 3:
            currentField = elementName
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth == 3 { text += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if depth == 3, let string = String(data: CDATABlock, encoding: .utf8) { text += string }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
    ) {
        switch depth {
        case 3:
            if let field = currentField { fields[field] = text }
            currentField = nil
        case 2:
            if let element = currentElement {
                do {
                    try onRecord(LaunchBoxRecord(element: element, fields: fields))
                } catch {
                    thrownError = error
                    aborted = true
                    parser.abortParsing()
                }
            }
            currentElement = nil
        default:
            break
        }
        depth -= 1
    }
}

/// Typed access to a record's text fields. Empty strings read as `nil`.
nonisolated public struct FieldReader: Sendable {
    public let fields: [String: String]

    public init(fields: [String: String]) {
        self.fields = fields
    }

    public subscript(key: String) -> String? {
        guard let raw = fields[key] else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func string(_ key: String) -> String? { self[key] }

    /// Multi-line text such as `Notes`, with internal newlines preserved.
    public func text(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        return value.replacingOccurrences(of: "\r\n", with: "\n")
    }

    public func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        guard let value = self[key]?.lowercased() else { return defaultValue }
        return value == "true" || value == "1" || value == "yes"
    }

    public func int(_ key: String) -> Int? {
        guard let value = self[key] else { return nil }
        return Int(value) ?? Double(value).map { Int($0) }
    }

    public func double(_ key: String) -> Double? {
        guard let value = self[key] else { return nil }
        return Double(value)
    }

    public func date(_ key: String) -> Date? {
        guard let value = self[key] else { return nil }
        return LaunchBoxDate.parse(value)
    }

    /// Splits LaunchBox's `a; b; c` lists.
    public func list(_ key: String, separator: Character = ";") -> [String] {
        guard let value = self[key] else { return [] }
        return value.split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Parses LaunchBox's .NET date strings, such as
/// `2017-12-11T09:09:53.788151-06:00` or `1988-10-05T02:00:00-05:00`.
nonisolated public enum LaunchBoxDate {
    private static let zoned: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    private static let unzoned: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let output: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    public static func parse(_ raw: String) -> Date? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 19 else { return nil }
        if value.hasPrefix("0001-01-01") { return nil }
        // Drop fractional seconds of any length: DateFormatter cannot parse them.
        let secondsEnd = value.index(value.startIndex, offsetBy: 19)
        if secondsEnd < value.endIndex, value[secondsEnd] == "." {
            var end = value.index(after: secondsEnd)
            while end < value.endIndex, value[end].isNumber { end = value.index(after: end) }
            value.removeSubrange(secondsEnd..<end)
        }
        if value.hasSuffix("Z") {
            value.removeLast()
            value += "+00:00"
        }
        return zoned.date(from: value) ?? unzoned.date(from: value)
    }

    public static func format(_ date: Date) -> String {
        output.string(from: date)
    }
}
