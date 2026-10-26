import Foundation

/// What happened when a game was started: the emulator, its command line,
/// the translated config, the planner's notes and the end of the emulator's
/// log. The Markdown form is for bug reports; a user pastes it as it is.
nonisolated public struct LaunchReport: Sendable {
    public var title: String
    public var platform: String
    public var pack: String?
    public var emulatorName: String
    public var executablePath: String
    public var commandLine: String
    public var workingDirectory: String
    public var notes: [String]
    public var startedAt: Date
    public var duration: TimeInterval?
    /// `nil` while the emulator is still running.
    public var exitStatus: Int32?
    public var configPath: String?
    public var configText: String?
    public var logPath: String?
    public var logExcerpt: String?
    public var appVersion: String

    public init(
        title: String, platform: String, pack: String?, emulatorName: String, executablePath: String,
        commandLine: String, workingDirectory: String, notes: [String], startedAt: Date, duration: TimeInterval?,
        exitStatus: Int32?, configPath: String?, configText: String?, logPath: String?, logExcerpt: String?,
        appVersion: String
    ) {
        self.title = title
        self.platform = platform
        self.pack = pack
        self.emulatorName = emulatorName
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.notes = notes
        self.startedAt = startedAt
        self.duration = duration
        self.exitStatus = exitStatus
        self.configPath = configPath
        self.configText = configText
        self.logPath = logPath
        self.logExcerpt = logExcerpt
        self.appVersion = appVersion
    }

    /// One line on how the launch ended.
    public var outcome: String {
        let took = duration.map { " after \(Self.clock($0))" } ?? ""
        switch exitStatus {
        case nil: return "Still running."
        case 0?: return "Finished normally\(took)."
        case let status?: return "Exited with code \(status)\(took)."
        }
    }

    public var markdown: String {
        var lines: [String] = []
        lines.append("# Launch report: \(title)")
        lines.append("")
        lines.append("\(appVersion), \(Self.iso.string(from: startedAt)).")
        lines.append("")
        lines.append("## Result")
        lines.append("")
        lines.append(outcome)
        lines.append("")
        lines.append("| | |")
        lines.append("|---|---|")
        lines.append("| Platform | \(Self.cell(platform)) |")
        if let pack { lines.append("| eXo pack | \(Self.cell(pack)) |") }
        lines.append("| Emulator | \(Self.cell(emulatorName)) — `\(executablePath)` |")
        lines.append("| Working folder | `\(workingDirectory)` |")
        if let logPath { lines.append("| Log | `\(logPath)` |") }
        lines.append("")
        lines.append("## Command")
        lines.append("")
        lines.append("```")
        lines.append(commandLine)
        lines.append("```")
        if !notes.isEmpty {
            lines.append("")
            lines.append("## Notes")
            lines.append("")
            for note in notes { lines.append("- \(note)") }
        }
        if let configText, !configText.isEmpty {
            lines.append("")
            lines.append("## Config" + (configPath.map { " (`\($0)`)" } ?? ""))
            lines.append("")
            lines.append("```ini")
            lines.append(configText.trimmingCharacters(in: .newlines))
            lines.append("```")
        }
        if let logExcerpt, !logExcerpt.isEmpty {
            lines.append("")
            lines.append("## Emulator log (end)")
            lines.append("")
            lines.append("```")
            lines.append(logExcerpt.trimmingCharacters(in: .newlines))
            lines.append("```")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The last `limit` lines of a log, for the report.
    public static func lastLines(of text: String, limit: Int = 80) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(limit).joined(separator: "\n")
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Pipes break a table cell.
    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
