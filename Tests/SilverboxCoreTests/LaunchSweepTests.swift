import Foundation
import Testing

@testable import SilverboxCore

/// Walks every eXoDOS game in the real library and translates its config
/// without starting anything. Opt in with `SILVERBOX_SWEEP=1 swift test
/// --filter LaunchSweep` (or `make sweep`); it reads thousands of files.
@Suite(
    "Launch sweep",
    .enabled(if: ProcessInfo.processInfo.environment["SILVERBOX_SWEEP"] == "1" && RealLibrary.isAvailable))
struct LaunchSweepTests {
    struct Tally {
        var games = 0
        var missingConfigFolder: [String] = []
        var missingConfig: [String] = []
        var missingArchive = 0
        var unknownBuild: [String] = []
        var builds: [String: Int] = [:]
        var variantsPerGame: [Int: Int] = [:]
        var windowsHelpers = 0
        var notes: [String: Int] = [:]
        var emptyAutoexec: [String] = []
        var translateFailures: [String] = []
    }

    @Test func translatesEveryConfig() throws {
        let started = Date()
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let scratch = try FixtureLibrary.scratchDirectory()
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let fm = FileManager.default
        var tally = Tally()

        for game in snapshot.games where game.launchKind == .dosBox {
            tally.games += 1
            guard let folder = planner.configFolder(for: game), fm.fileExists(atPath: folder.path) else {
                tally.missingConfigFolder.append(game.title)
                continue
            }
            let archive = snapshot.root.gamesDirectory.appendingPathComponent("\(game.launcherBaseName).zip")
            if !fm.fileExists(atPath: archive.path), snapshot.installedLocation(for: game) == nil {
                tally.missingArchive += 1
            }
            if let build = planner.eXoDOSBuild(for: game) {
                tally.builds[build.displayName, default: 0] += 1
            } else {
                tally.unknownBuild.append(game.title)
            }
            let variants = planner.variants(for: game)
            tally.variantsPerGame[variants.count, default: 0] += 1
            tally.windowsHelpers += variants.filter(\.needsWindowsHelper).count

            let configURL = variants.first?.configURL ?? folder.appendingPathComponent("dosbox.conf")
            guard let data = fm.contents(atPath: configURL.path) else {
                tally.missingConfig.append(game.title)
                continue
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            let kind = planner.recommendedEmulator(for: game)
            let translator = ConfigTranslator(
                root: snapshot.root, emulator: kind, options: LaunchOptions(),
                fluidSynthAvailable: false, fallbackDirectories: [folder])
            let result = translator.translate(DOSBoxConfigDocument.parse(text))
            if result.document.autoexecLines.isEmpty { tally.emptyAutoexec.append(game.title) }
            if result.document.serialized().isEmpty { tally.translateFailures.append(game.title) }
            for note in result.notes {
                tally.notes[Self.generalise(note), default: 0] += 1
            }
        }

        let seconds = Date().timeIntervalSince(started)
        print(
            """
            === Launch sweep over \(tally.games) eXoDOS games in \(String(format: "%.0f", seconds)) s
            config folder missing: \(tally.missingConfigFolder.count) \(tally.missingConfigFolder.prefix(10))
            dosbox.conf missing:   \(tally.missingConfig.count) \(tally.missingConfig.prefix(10))
            archive missing:       \(tally.missingArchive)
            build unknown:         \(tally.unknownBuild.count) \(tally.unknownBuild.prefix(10))
            builds:                \(tally.builds.sorted { $0.value > $1.value })
            variants per game:     \(tally.variantsPerGame.sorted { $0.key < $1.key })
            windows helper menus:  \(tally.windowsHelpers)
            empty autoexec:        \(tally.emptyAutoexec.count) \(tally.emptyAutoexec.prefix(10))
            notes:
            """)
        for (note, count) in tally.notes.sorted(by: { $0.value > $1.value }) {
            print("  \(count)\t\(note)")
        }

        #expect(tally.games > 7000)
        #expect(tally.missingConfigFolder.count < 20, "\(tally.missingConfigFolder.prefix(20))")
        #expect(tally.missingConfig.count < 20, "\(tally.missingConfig.prefix(20))")
        #expect(tally.unknownBuild.count < 20, "\(tally.unknownBuild.prefix(20))")
        #expect(tally.emptyAutoexec.count < 20, "\(tally.emptyAutoexec.prefix(20))")
        #expect(tally.translateFailures.isEmpty, "\(tally.translateFailures.prefix(20))")
    }

    /// Collapses paths and numbers so notes group by cause.
    static func generalise(_ note: String) -> String {
        var text = note
        if let range = text.range(of: "/Volumes/") {
            let rest = text[range.lowerBound...]
            let end = rest.firstIndex(where: { $0 == " " || $0 == ";" || $0 == "," || $0 == ")" }) ?? rest.endIndex
            text.replaceSubrange(range.lowerBound..<end, with: "<path>")
        }
        return text.replacing(/\d+/, with: "N")
    }
}
