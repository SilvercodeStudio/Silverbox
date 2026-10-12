import Foundation

/// A DOSBox-style INI document. Keys are lower-cased; the `[autoexec]`
/// section keeps raw command lines instead of key/value entries.
nonisolated public struct DOSBoxConfigDocument: Sendable, Hashable {
    nonisolated public struct Entry: Sendable, Hashable {
        public var key: String
        public var value: String
        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    nonisolated public struct Section: Sendable, Hashable {
        public var name: String
        public var entries: [Entry]
        public var lines: [String]

        public init(name: String, entries: [Entry] = [], lines: [String] = []) {
            self.name = name
            self.entries = entries
            self.lines = lines
        }

        public var isAutoexec: Bool { name == "autoexec" }
        public var isEmpty: Bool { entries.isEmpty && lines.isEmpty }

        public func value(_ key: String) -> String? {
            entries.last { $0.key == key.lowercased() }?.value
        }
    }

    public var header: [String]
    public var sections: [Section]

    public init(header: [String] = [], sections: [Section] = []) {
        self.header = header
        self.sections = sections
    }

    public static func parse(_ text: String) -> DOSBoxConfigDocument {
        var document = DOSBoxConfigDocument()
        var current: Section?
        func flush() {
            if let section = current { document.sections.append(section) }
            current = nil
        }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                flush()
                let name = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces).lowercased()
                current = Section(name: name)
                continue
            }
            if line.isEmpty { continue }
            if var section = current, section.isAutoexec {
                if line.hasPrefix("#") { continue }
                section.lines.append(line)
                current = section
                continue
            }
            if line.hasPrefix("#") || line.hasPrefix(";") {
                if current == nil {
                    document.header.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
                }
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            if current == nil { current = Section(name: "") }
            current?.entries.append(Entry(key: key, value: value))
        }
        flush()
        return document
    }

    public func serialized() -> String {
        var out: [String] = []
        for line in header { out.append("# \(line)") }
        if !header.isEmpty { out.append("") }
        for section in sections where !section.isEmpty && !section.name.isEmpty {
            out.append("[\(section.name)]")
            for entry in section.entries { out.append("\(entry.key) = \(entry.value)") }
            for line in section.lines { out.append(line) }
            out.append("")
        }
        return out.joined(separator: "\n") + "\n"
    }

    public func section(_ name: String) -> Section? {
        sections.first { $0.name == name.lowercased() }
    }

    public func value(_ section: String, _ key: String) -> String? {
        self.section(section)?.value(key)
    }

    /// Sets `key` in `section`, replacing any existing entries for it and
    /// creating the section when needed.
    public mutating func set(_ section: String, _ key: String, _ value: String) {
        let name = section.lowercased(), lowerKey = key.lowercased()
        if let offset = sections.firstIndex(where: { $0.name == name }) {
            sections[offset].entries.removeAll { $0.key == lowerKey }
            sections[offset].entries.append(Entry(key: lowerKey, value: value))
        } else {
            let section = Section(name: name, entries: [Entry(key: lowerKey, value: value)])
            // Keep [autoexec] last, where DOSBox users expect it.
            if let autoexec = sections.firstIndex(where: { $0.isAutoexec }) {
                sections.insert(section, at: autoexec)
            } else {
                sections.append(section)
            }
        }
    }

    public mutating func remove(_ section: String, _ key: String) {
        let name = section.lowercased(), lowerKey = key.lowercased()
        guard let offset = sections.firstIndex(where: { $0.name == name }) else { return }
        sections[offset].entries.removeAll { $0.key == lowerKey }
    }

    public var autoexecLines: [String] {
        get { section("autoexec")?.lines ?? [] }
        set {
            if let offset = sections.firstIndex(where: { $0.isAutoexec }) {
                sections[offset].lines = newValue
            } else {
                sections.append(Section(name: "autoexec", lines: newValue))
            }
        }
    }
}
