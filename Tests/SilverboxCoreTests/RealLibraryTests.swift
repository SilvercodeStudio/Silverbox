import Foundation
import Testing

@testable import SilverboxCore

/// Checks against a real eXoDOS install when one is mounted. Skipped otherwise.
@Suite("Real eXoDOS library", .enabled(if: RealLibrary.isAvailable))
struct RealLibraryTests {
    @Test func loadsEveryPlatform() throws {
        let start = Date()
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let seconds = Date().timeIntervalSince(start)
        print(
            "Loaded \(snapshot.games.count) games from \(snapshot.platforms.count) platforms in \(String(format: "%.2f", seconds)) s"
        )
        #expect(snapshot.games.count > 7000)
        #expect(snapshot.platforms.contains { $0.name == "MS-DOS" })
        #expect(snapshot.dosboxIndex.count > 7000)
        let ultima = try #require(snapshot.games.first { $0.title == "Ultima V: Warriors of Destiny" })
        #expect(ultima.gameFolderName == "ultima5")
        // eXoDOS 6.04 moved Ultima V from DOSBox ECE to Staging; any known build is fine.
        let build = try #require(snapshot.dosboxIndex.build(forLauncherBaseName: ultima.launcherBaseName))
        print("Ultima V runs with \(build.displayName)")
        #expect(build.family != .custom)
        #expect(!snapshot.tree.isEmpty)
    }

    /// eXo's Lite script finds a game in the torrent by its archive's name;
    /// Silverbox finds it by the path the installer looks for. The two must
    /// agree for the eXoDOS games the torrent has.
    @Test func eXoDOSTorrentListsEveryGameArchive() throws {
        let torrent = try #require(RealLibrary.root.torrentURLs.first { $0.lastPathComponent == "eXoDOS.torrent" })
        let list = try TorrentFileList(contentsOf: torrent)
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let installer = GameInstaller(snapshot: snapshot)
        let games = snapshot.games.filter { $0.eXoPack == .dos && !$0.isEXoSetupScript }
        var missing: [String] = []
        for game in games {
            guard let plan = installer.plan(for: game) else { continue }
            let path = "eXo/eXoDOS/\(plan.archiveURL.lastPathComponent)"
            if list.file(at: path) == nil { missing.append(game.title) }
        }
        print("\(list.files.count) files in the torrent; \(missing.count) of \(games.count) eXoDOS games not in it")
        #expect(games.count > 7000)
        // eXo's updates add games after the torrent was made (Quake II
        // (Q2DOS) and Sigil II in 6.04); those come with the update instead.
        #expect(missing.count * 100 < games.count, Comment(rawValue: missing.joined(separator: " | ")))
    }

    /// Decodes the first file of each bundled-decoder format in the Music folder.
    @Test func decodesRealMusicFiles() throws {
        let folder = RealLibrary.root.url.appendingPathComponent("Music/MS-DOS")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for ext in ["ogg", "mod", "s3m", "xm"] {
            guard let url = files.first(where: { $0.pathExtension.lowercased() == ext }) else { continue }
            let decoder = try MusicDecoders.decoder(for: url)
            var buffer = [Int16](repeating: 0, count: 4096 * decoder.channelCount)
            var frames = 0
            var peak = 0
            while frames < decoder.sampleRate * 2 {
                let got = buffer.withUnsafeMutableBufferPointer {
                    decoder.read(into: $0.baseAddress!, frameCount: 4096)
                }
                if got == 0 { break }
                frames += got
                peak = max(peak, buffer[..<(got * decoder.channelCount)].map { abs(Int($0)) }.max() ?? 0)
            }
            print(
                "\(url.lastPathComponent): \(decoder.sampleRate) Hz, \(decoder.channelCount) ch, title \(decoder.title ?? "-"), \(frames) frames, peak \(peak)"
            )
            #expect(frames > 0, Comment(rawValue: url.lastPathComponent))
            #expect(peak > 0, Comment(rawValue: url.lastPathComponent))
        }
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
        let titles = [
            "Super Tetris", "Ultima I: The First Age of Darkness", "The 7th Guest",
            "Western Front: The Liberation of Europe 1944-1945", "3 Skulls of the Toltecs",
        ]
        for title in titles {
            guard let game = snapshot.games.first(where: { $0.title == title }),
                let folder = planner.configFolder(for: game)
            else { continue }
            let url = folder.appendingPathComponent("dosbox.conf")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for kind in EmulatorKind.dosBox {
                let translator = ConfigTranslator(root: snapshot.root, emulator: kind, options: LaunchOptions())
                let result = translator.translate(DOSBoxConfigDocument.parse(text))
                #expect(!result.document.autoexecLines.isEmpty)
                print("\(title) → \(kind.displayName): \(result.notes)")
            }
        }
    }

    /// Every eXoWin9x entry is a Windows 9x game, and each game unpacked in
    /// the library plans a Windows 98 boot whose disks and CDs all exist.
    @Test func plansUnpackedWindows9xGames() throws {
        let scratch = try FixtureLibrary.scratchDirectory()
        let localStore = LocalStore(directory: scratch.appendingPathComponent("local", isDirectory: true))
        let snapshot = try LibraryLoader(root: RealLibrary.root, localStore: localStore).load()
        let games = snapshot.games.filter { $0.platform == "Windows 9x" && $0.applicationPath.contains("!win9x") }
        guard !games.isEmpty else { return }
        #expect(games.allSatisfy { $0.launchKind == .windows9x })

        let emulator = try FixtureLibrary.fakeEmulator(.dosboxX, in: scratch)
        let planner = LaunchPlanner(snapshot: snapshot, scratchDirectory: scratch)
        var planned = 0
        for game in games where snapshot.isInstalled(game) {
            do {
                let plan = try planner.plan(game: game, variant: nil, emulator: emulator, options: LaunchOptions())
                let missing = plan.notes.filter { $0.hasPrefix("Could not find") }
                #expect(missing.isEmpty, "\(game.title): \(missing)")
                #expect(DOSBoxConfigDocument.parse(plan.configText).autoexecLines.contains { $0.hasPrefix("vhdmake") })
                planned += 1
            } catch LaunchPlanError.needs86Box {
                continue
            }
        }
        print("Planned \(planned) unpacked eXoWin9x games")
    }
}

nonisolated enum RealLibrary {
    static let root = LibraryRoot(
        url: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SILVERBOX_TEST_LIBRARY"] ?? "/Volumes/eXoDOS_ro")
    )
    static var isAvailable: Bool { FileManager.default.fileExists(atPath: root.platformsFile.path) }
}
