import Foundation

/// One way to launch a game. Most games have a single `dosbox.conf`; some
/// ship an `exception.bat` menu that offers alternatives such as an
/// upgraded version with a second config file.
nonisolated public struct LaunchVariant: Identifiable, Hashable, Sendable {
    public var title: String
    public var configURL: URL
    /// True when the original menu entry also started a Windows helper that
    /// has no Mac equivalent.
    public var needsWindowsHelper: Bool

    /// The config's file name for DOSBox games; the folder path inside the
    /// game for ScummVM games.
    public var id: String

    /// For ScummVM games, `configURL` is the variant's folder.
    public init(title: String, configURL: URL, needsWindowsHelper: Bool = false, id: String? = nil) {
        self.title = title
        self.configURL = configURL
        self.needsWindowsHelper = needsWindowsHelper
        self.id = id ?? configURL.lastPathComponent
    }
}

nonisolated public enum LaunchVariantDetector {
    /// Lists the launch variants in a game's `!dos/<game>` folder.
    public static func variants(inGameConfigFolder folder: URL) -> [LaunchVariant] {
        let fm = FileManager.default
        let exception = folder.appendingPathComponent("exception.bat")
        if let data = fm.contents(atPath: exception.path) {
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let parsed = parseExceptionScript(text, folder: folder)
            if !parsed.isEmpty { return parsed }
        }
        guard
            let entries = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else {
            return []
        }
        let confs = entries.filter { $0.pathExtension.lowercased() == "conf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return confs.map { url in
            let stem = url.deletingPathExtension().lastPathComponent
            let title = stem.lowercased() == "dosbox" ? "Default" : stem
            return LaunchVariant(title: title, configURL: url)
        }
    }

    nonisolated(unsafe) private static let pressPattern =
        #/(?i)^\s*echo\s+Press\s+(?<key>\S)\s+(?:to|for)\s+(?:play|run|launch|start)?\s*(?<title>.+?)\s*$/#
    nonisolated(unsafe) private static let choicePattern = #/(?i)choice\s+/C:(?<keys>\S+)/#
    nonisolated(unsafe) private static let errorlevelPattern =
        #/(?i)^\s*if\s+errorlevel\s*=?\s*(?<level>\d+)\s+goto\s+(?<label>\S+)/#
    nonisolated(unsafe) private static let labelPattern = #/^\s*:(?<label>\S+)\s*$/#
    nonisolated(unsafe) private static let confPattern = #/(?i)-conf\s+"?%var%\\(?<name>[^"\s]+\.conf)"?/#

    /// Parses an eXoDOS `exception.bat` menu into variants.
    static func parseExceptionScript(_ text: String, folder: URL) -> [LaunchVariant] {
        let lines = text.components(separatedBy: .newlines)
        var titles: [String: String] = [:]  // menu key → title
        var orderedKeys: [String] = []
        var choiceKeys: [Character] = []
        var labelForLevel: [Int: String] = [:]
        var confForLabel: [String: String] = [:]
        var helperForLabel: Set<String> = []
        var currentLabel: String?

        for line in lines {
            if let match = line.firstMatch(of: pressPattern) {
                let key = String(match.key).uppercased()
                if titles[key] == nil { orderedKeys.append(key) }
                titles[key] = String(match.title)
                continue
            }
            if let match = line.firstMatch(of: choicePattern), choiceKeys.isEmpty {
                choiceKeys = Array(String(match.keys).uppercased())
                continue
            }
            if let match = line.firstMatch(of: errorlevelPattern), let level = Int(match.level) {
                labelForLevel[level] = String(match.label).lowercased()
                continue
            }
            if let match = line.wholeMatch(of: labelPattern) {
                currentLabel = String(match.label).lowercased()
                continue
            }
            guard let label = currentLabel else { continue }
            if let match = line.firstMatch(of: confPattern), confForLabel[label] == nil {
                confForLabel[label] = String(match.name)
            }
            if line.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix("start ") {
                helperForLabel.insert(label)
            }
        }

        var variants: [LaunchVariant] = []
        for key in orderedKeys {
            guard let title = titles[key], let position = choiceKeys.firstIndex(of: Character(key)) else { continue }
            let level = position + 1
            guard let label = labelForLevel[level], let conf = confForLabel[label] else { continue }
            let url = folder.appendingPathComponent(conf)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            variants.append(
                LaunchVariant(title: title, configURL: url, needsWindowsHelper: helperForLabel.contains(label)))
        }
        return variants
    }
}
