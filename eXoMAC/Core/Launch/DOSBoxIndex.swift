import Foundation

/// Which DOSBox build eXoDOS bundles for a game, read from `eXo/util/dosbox.txt`:
///
/// ```
/// Ultima V - Warriors of Destiny (1988):ece4230\dosbox.exe
/// Ultima I - The First Age of Darkness (1986):staging0.81.0a\dosbox.exe
/// ```
nonisolated public struct DOSBoxIndex: Sendable, Hashable {
    public private(set) var buildByGame: [String: String]

    public init(buildByGame: [String: String] = [:]) {
        self.buildByGame = buildByGame
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        self = Self.parse(text)
    }

    public static func parse(_ text: String) -> DOSBoxIndex {
        var map: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = line.lastIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let path = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !path.isEmpty else { continue }
            map[name.lowercased()] = path
        }
        return DOSBoxIndex(buildByGame: map)
    }

    public var count: Int { buildByGame.count }

    public func build(forLauncherBaseName name: String) -> EXoDOSBuild? {
        guard let path = buildByGame[name.lowercased()] else { return nil }
        return EXoDOSBuild(rawPath: path)
    }
}

/// One of the DOSBox builds shipped in `eXo/emulators/dosbox/`.
nonisolated public struct EXoDOSBuild: Hashable, Sendable, Codable {
    nonisolated public enum Family: String, Sendable, Codable, Hashable {
        case vanilla = "DOSBox 0.74"
        case ece = "DOSBox ECE"
        case staging = "DOSBox Staging"
        case daum = "DOSBox SVN Daum"
        case x = "DOSBox-X"
        case custom = "Custom DOSBox build"
    }

    public var rawPath: String
    public var folder: String
    public var family: Family

    public init(rawPath: String) {
        self.rawPath = rawPath
        let components = WindowsPath.components(of: rawPath)
        let folder = components.count > 1 ? components[0] : ""
        self.folder = folder
        let lowered = folder.lowercased()
        if lowered.isEmpty || lowered == "dosbox0.74" {
            family = .vanilla
        } else if lowered.hasPrefix("ece") {
            family = .ece
        } else if lowered.hasPrefix("staging") {
            family = .staging
        } else if lowered.hasPrefix("daum") {
            family = .daum
        } else if lowered == "x" || lowered == "x2" || lowered.hasPrefix("dosbox-x") {
            family = .x
        } else {
            family = .custom
        }
    }

    /// A short label such as `DOSBox ECE r4230` or `DOSBox Staging 0.81.0a`.
    public var displayName: String {
        switch family {
        case .vanilla: return "DOSBox 0.74"
        case .ece: return "DOSBox ECE \(folder.dropFirst(3).isEmpty ? "" : "r" + folder.dropFirst(3))".trimmingCharacters(in: .whitespaces)
        case .staging: return "DOSBox Staging \(folder.dropFirst(7))".trimmingCharacters(in: .whitespaces)
        case .daum: return "DOSBox SVN Daum"
        case .x: return "DOSBox-X"
        case .custom: return "Custom build (\(folder))"
        }
    }

    /// The Mac emulator closest to the Windows build eXoDOS chose.
    public var recommendedEmulator: EmulatorKind {
        switch family {
        case .daum, .x: return .dosboxX
        case .vanilla, .ece, .staging, .custom: return .dosboxStaging
        }
    }
}
