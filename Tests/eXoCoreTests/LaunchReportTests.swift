import Foundation
import Testing

@testable import eXoCore

@Suite("Launch report")
struct LaunchReportTests {
    static func report(exitStatus: Int32?, duration: TimeInterval? = 83) -> LaunchReport {
        LaunchReport(
            title: "Ultima V: Warriors of Destiny", platform: "MS-DOS", pack: "eXoDOS",
            emulatorName: "DOSBox Staging", executablePath: "/Applications/DOSBox Staging.app/Contents/MacOS/dosbox",
            commandLine: "\"/Applications/DOSBox Staging.app/Contents/MacOS/dosbox\" -conf ultima5.conf",
            workingDirectory: "/Volumes/eXoDOS_ro/eXo/eXoDOS/ultima5", notes: ["Used the MT-32 ROMs from eXo"],
            startedAt: Date(timeIntervalSince1970: 1_760_000_000), duration: duration, exitStatus: exitStatus,
            configPath: "/tmp/ultima5.conf", configText: "[sdl]\nfullscreen = false\n", logPath: "/tmp/u5.log",
            logExcerpt: "MIDI: Opened device\nExit", appVersion: "Silverbox 0.1 (2)")
    }

    @Test func describesTheOutcome() {
        #expect(Self.report(exitStatus: 0).outcome == "Finished normally after 1:23.")
        #expect(Self.report(exitStatus: 1).outcome == "Exited with code 1 after 1:23.")
        #expect(Self.report(exitStatus: nil, duration: nil).outcome == "Still running.")
        #expect(LaunchReport.clock(3725) == "1:02:05")
    }

    @Test func writesMarkdownForABugReport() {
        let markdown = Self.report(exitStatus: 1).markdown
        #expect(markdown.hasPrefix("# Launch report: Ultima V: Warriors of Destiny\n\nSilverbox 0.1 (2), 2025-"))
        #expect(markdown.contains("## Result\n\nExited with code 1 after 1:23.\n"))
        #expect(markdown.contains("| eXo pack | eXoDOS |"))
        #expect(
            markdown.contains(
                "| Emulator | DOSBox Staging — `/Applications/DOSBox Staging.app/Contents/MacOS/dosbox` |"))
        #expect(
            markdown.contains(
                "## Command\n\n```\n\"/Applications/DOSBox Staging.app/Contents/MacOS/dosbox\" -conf ultima5.conf\n```")
        )
        #expect(markdown.contains("## Notes\n\n- Used the MT-32 ROMs from eXo\n"))
        #expect(markdown.contains("## Config (`/tmp/ultima5.conf`)\n\n```ini\n[sdl]\nfullscreen = false\n```"))
        #expect(markdown.contains("## Emulator log (end)\n\n```\nMIDI: Opened device\nExit\n```\n"))
        #expect(markdown.hasSuffix("```\n"))
    }

    @Test func keepsOnlyTheEndOfALog() {
        let log = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let tail = LaunchReport.lastLines(of: log, limit: 3)
        #expect(tail == "line 98\nline 99\nline 100")
        #expect(LaunchReport.lastLines(of: "short") == "short")
    }
}
