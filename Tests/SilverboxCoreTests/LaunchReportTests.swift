import Foundation
import Testing

@testable import SilverboxCore

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

@Suite("Problem report")
struct ProblemReportTests {
    static let details = ProblemReport.Details(
        program: "Silverbox 0.3 (4) · 536e697", system: "macOS 26.2 (Build 25C56), Mac15,8, Apple silicon",
        collections: ["eXoDOS: 7,666 games"], emulators: ["DOSBox Staging (FluidSynth)", "DOSBox-X"])

    static func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func fillsInANewIssue() {
        let url = ProblemReport.issueURL(Self.details)
        #expect(url.absoluteString.hasPrefix("https://github.com/SilvercodeStudio/Silverbox/issues/new?body="))
        let body = Self.query(url)["body"] ?? ""
        #expect(body.hasPrefix("### What happened\n\n\n### What you expected\n"))
        #expect(
            body.hasSuffix(
                """
                ---
                Silverbox 0.3 (4) · 536e697
                macOS 26.2 (Build 25C56), Mac15,8, Apple silicon
                Collections:
                - eXoDOS: 7,666 games
                Emulators:
                - DOSBox Staging (FluidSynth)
                - DOSBox-X
                """))
    }

    @Test func saysNoneForAnEmptyList() {
        let details = ProblemReport.Details(
            program: "Silverbox 0.3 (4)", system: "macOS", collections: [], emulators: [])
        let body = ProblemReport.issueBody(details)
        #expect(body.hasSuffix("Collections: none\nEmulators: none"))
    }

    @Test func fillsInANewDiscussion() {
        let url = ProblemReport.feedbackURL(program: "Silverbox 0.3 (4)", system: "macOS 26.2")
        #expect(url.absoluteString.hasPrefix("https://github.com/SilvercodeStudio/Silverbox/discussions/new?"))
        let query = Self.query(url)
        #expect(query["category"] == "general")
        #expect(query["body"]?.hasSuffix("---\nSilverbox 0.3 (4)\nmacOS 26.2") == true)
    }

    @Test func namesTheMac() {
        #expect(ProblemReport.system.hasPrefix("macOS "))
    }
}
