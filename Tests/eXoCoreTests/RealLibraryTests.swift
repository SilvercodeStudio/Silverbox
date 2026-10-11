import Foundation
import Testing
@testable import eXoCore

/// Checks against a real eXoDOS install when one is mounted. Skipped otherwise.
@Suite("Real eXoDOS library", .enabled(if: RealLibrary.isAvailable))
struct RealLibraryTests {
    @Test func loadsEveryPlatform() throws {
        let start = Date()
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let seconds = Date().timeIntervalSince(start)
        print("Loaded \(snapshot.games.count) games from \(snapshot.platforms.count) platforms in \(String(format: "%.2f", seconds)) s")
        #expect(snapshot.games.count > 7000)
        #expect(snapshot.platforms.contains { $0.name == "MS-DOS" })
        #expect(snapshot.dosboxIndex.count > 7000)
        let ultima = try #require(snapshot.games.first { $0.title == "Ultima V: Warriors of Destiny" })
        #expect(ultima.gameFolderName == "ultima5")
        #expect(snapshot.dosboxIndex.build(forLauncherBaseName: ultima.launcherBaseName)?.family == .ece)
        #expect(!snapshot.tree.isEmpty)
    }

    @Test func locatesMediaAndTranslatesConfigs() async throws {
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let catalog = MediaCatalog(snapshot: snapshot)
        let ultima = try #require(snapshot.games.first { $0.title == "Ultima V: Warriors of Destiny" })
        let cover = await catalog.firstImage(for: ultima)
        #expect(cover?.url.lastPathComponent == "Ultima V_ Warriors of Destiny-01.jpg")
        #expect(await catalog.video(for: ultima) != nil)
        #expect(await catalog.manual(for: ultima) != nil)
        #expect(await catalog.music(for: ultima) != nil)
        #expect(await catalog.extras(for: ultima).count >= 10)

        let scratch = try FixtureLibrary.scratchDirectory()
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        let variants = planner.variants(for: ultima)
        #expect(variants.count == 4)

        // Translate a sample of configs of each family and make sure nothing explodes.
        let titles = ["Super Tetris", "Ultima I: The First Age of Darkness", "The 7th Guest", "Western Front: The Liberation of Europe 1944-1945", "3 Skulls of the Toltecs"]
        for title in titles {
            guard let game = snapshot.games.first(where: { $0.title == title }), let folder = planner.configFolder(for: game) else { continue }
            let url = folder.appendingPathComponent("dosbox.conf")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for kind in EmulatorKind.allCases {
                let translator = ConfigTranslator(root: snapshot.root, emulator: kind, options: LaunchOptions())
                let result = translator.translate(DOSBoxConfigDocument.parse(text))
                #expect(!result.document.autoexecLines.isEmpty)
                print("\(title) → \(kind.displayName): \(result.notes)")
            }
        }
    }
}

nonisolated enum RealLibrary {
    static let root = LibraryRoot(url: URL(fileURLWithPath: ProcessInfo.processInfo.environment["EXOMAC_TEST_LIBRARY"] ?? "/Volumes/eXoDOS_ro"))
    static var isAvailable: Bool { FileManager.default.fileExists(atPath: root.platformsFile.path) }
}
