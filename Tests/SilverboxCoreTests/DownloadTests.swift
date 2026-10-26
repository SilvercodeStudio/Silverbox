import Foundation
import Testing

@testable import SilverboxCore

/// Bencoding for test torrents.
nonisolated private func bencode(_ value: Any) -> Data {
    switch value {
    case let number as Int: return Data("i\(number)e".utf8)
    case let text as String: return Data("\(text.utf8.count):\(text)".utf8)
    case let list as [Any]: return Data("l".utf8) + list.map(bencode).reduce(Data(), +) + Data("e".utf8)
    case let dictionary as [String: Any]:
        return Data("d".utf8)
            + dictionary.keys.sorted().map { bencode($0) + bencode(dictionary[$0]!) }.reduce(Data(), +)
            + Data("e".utf8)
    default: fatalError("Cannot bencode \(value)")
    }
}

/// A multi-file torrent named `eXoDOS` that lists `files` (path, length) in order.
nonisolated private func torrent(_ files: [(String, Int)]) -> Data {
    bencode([
        "announce": "udp://tracker.example:6969/announce",
        "info": [
            "name": "eXoDOS", "piece length": 8_388_608, "pieces": "",
            "files": files.map { ["length": $0.1, "path": $0.0.split(separator: "/").map(String.init)] },
        ] as [String: Any],
    ])
}

@Suite struct DownloadTests {
    @Test func readsTorrentFileList() throws {
        let data = torrent([("eXoDOS Manual.pdf", 10), ("eXo/eXoDOS/Mini Game (1990).zip", 2048)])
        let list = try TorrentFileList(url: URL(fileURLWithPath: "/tmp/eXoDOS.torrent"), data: data)
        #expect(list.name == "eXoDOS")
        #expect(list.files.map(\.index) == [1, 2])
        #expect(list.file(at: "eXo/eXoDOS/Mini Game (1990).zip")?.length == 2048)
        // The Mac's file system ignores case, and so does the lookup.
        #expect(list.file(at: "eXo/exodos/mini game (1990).zip")?.index == 2)
        #expect(list.file(at: "eXo/eXoDOS/Other.zip") == nil)

        let single = bencode(["info": ["name": "game.zip", "length": 5, "piece length": 16384, "pieces": ""]])
        let one = try TorrentFileList(url: URL(fileURLWithPath: "/tmp/one.torrent"), data: single)
        #expect(one.files == [TorrentFileList.File(index: 1, path: "game.zip", length: 5)])

        #expect(throws: BencodeError.self) { try Bencode.decode(Data("d4:infoi1e".utf8)) }
        #expect(throws: BencodeError.self) { try Bencode.decode(Data("5:abc".utf8)) }
    }

    @Test func readsAria2Readout() {
        let progress = DownloadProgress(readout: "[#b15d3a 917504B/16777216B(5%) CN:3 SD:1 DL:466377B ETA:4s]")
        #expect(progress?.bytesDone == 917_504)
        #expect(progress?.bytesTotal == 16_777_216)
        #expect(progress?.bytesPerSecond == 466_377)
        #expect(progress?.connections == 3)
        #expect(progress?.seeders == 1)
        let starting = DownloadProgress(readout: "[#b15d3a 0B/0B CN:0 DL:0B]")
        #expect(starting?.fraction == nil)
        #expect(DownloadProgress(readout: "FILE: eXoDOS/13791.zip") == nil)
        #expect(DownloadProgress(readout: "[#b15d3a SEED(0.0) CN:0]") == nil)
    }

    /// A writable library that lacks Mini Game's archive, with an eXo torrent
    /// that lists the archive and its GameData zip, made from real zips in
    /// `source/`.
    private struct LiteLibrary {
        let scratch: URL
        let root: LibraryRoot
        let game: Game
        let gameZip: URL
        let gameDataZip: URL

        var snapshot: LibrarySnapshot {
            LibrarySnapshot(
                root: root, games: [game], platforms: [], categories: [], platformFolders: [],
                playlists: [], parents: [], alternateNames: [], additionalApplications: [],
                installedGamePaths: LibraryLoader.installedGamePaths(in: root.eXoDirectory))
        }

        init() async throws {
            scratch = try FixtureLibrary.scratchDirectory()
            root = LibraryRoot(url: scratch.appendingPathComponent("library", isDirectory: true))
            game = Game(
                id: "mini", title: "Mini Game", platform: "MS-DOS",
                applicationPath: "eXo\\eXoDOS\\!dos\\MiniGame\\Mini Game (1990).bat",
                rootFolder: "eXo\\eXoDOS\\!dos\\MiniGame")
            let fm = FileManager.default
            let stage = scratch.appendingPathComponent("stage", isDirectory: true)
            let source = scratch.appendingPathComponent("source", isDirectory: true)
            try fm.createDirectory(at: stage.appendingPathComponent("MiniGame"), withIntermediateDirectories: true)
            try fm.createDirectory(
                at: stage.appendingPathComponent("eXo/eXoDOS/!dos/MiniGame/Extras"), withIntermediateDirectories: true)
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            try "hello".write(
                to: stage.appendingPathComponent("MiniGame/GAME.EXE"), atomically: true, encoding: .utf8)
            try "map".write(
                to: stage.appendingPathComponent("eXo/eXoDOS/!dos/MiniGame/Extras/Map.txt"), atomically: true,
                encoding: .utf8)
            gameZip = source.appendingPathComponent("game.zip")
            gameDataZip = source.appendingPathComponent("gamedata.zip")
            for (zip, folder) in [(gameZip, "MiniGame"), (gameDataZip, "eXo")] {
                let result = try await CommandRunner.run(
                    executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", "-r", zip.path, folder],
                    workingDirectory: stage)
                #expect(result.status == 0, Comment(rawValue: result.output))
            }
            func size(_ url: URL) throws -> Int {
                try #require(fm.attributesOfItem(atPath: url.path)[.size] as? Int)
            }
            let aria = root.eXoDirectory.appendingPathComponent("util/aria", isDirectory: true)
            try fm.createDirectory(at: aria, withIntermediateDirectories: true)
            try fm.createDirectory(at: root.gamesDirectory, withIntermediateDirectories: true)
            try torrent([
                ("eXoDOS Manual.pdf", 10),
                ("Content/GameData/eXoDOS/Mini Game (1990).zip", try size(gameDataZip)),
                ("eXo/eXoDOS/Mini Game (1990).zip", try size(gameZip)),
            ]).write(to: aria.appendingPathComponent("eXoDOS.torrent"))
        }

        /// A stand-in for aria2c: it reports progress, writes the selected
        /// files under their numbers in `--dir` and exits with `status`.
        func fakeAria2(status: Int32 = 0) throws -> URL {
            let url = scratch.appendingPathComponent("aria2c")
            try """
            #!/bin/sh
            for argument in "$@"; do
              case "$argument" in --dir=*) dir="${argument#--dir=}" ;; esac
            done
            echo "[#abc123 0B/16777216B(0%) CN:0 SD:0 DL:0B]"
            echo "[#abc123 8388608B/16777216B(50%) CN:2 SD:1 DL:1048576B ETA:8s]"
            if [ \(status) -ne 0 ]; then
              echo "10/26 11:30:00 [ERROR] CUID#7 - Not enough disk space."
              exit \(status)
            fi
            cp "\(gameZip.path)" "$dir/3.zip"
            cp "\(gameDataZip.path)" "$dir/2.zip"
            echo "[#abc123 16777216B/16777216B(100%) CN:2 SD:1 DL:1048576B]"
            """.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }
    }

    @Test func plansADownloadForAMissingArchive() async throws {
        let library = try await LiteLibrary()
        let installer = GameInstaller(snapshot: library.snapshot)
        let plan = try #require(installer.plan(for: library.game))
        #expect(!plan.archiveExists)
        let download = try #require(installer.downloadPlan(for: plan))
        #expect(download.items.map(\.file.index) == [3, 2])
        #expect(download.items[0].destination == plan.archiveURL)
        #expect(
            download.items[1].destination
                == library.root.url.appendingPathComponent("Content/GameData/eXoDOS/Mini Game (1990).zip"))
        #expect(download.isWritable)
        #expect(download.totalBytes == download.gameBytes + download.extrasBytes)
        #expect(download.scratchDirectory.lastPathComponent == "eXoDOS-3-2")
        #expect(
            download.workDirectory == library.root.eXoDirectory.appendingPathComponent("DOWNLOAD", isDirectory: true))

        let dht = library.scratch.appendingPathComponent("dht.dat")
        let arguments = TorrentDownloader(executable: URL(fileURLWithPath: "/bin/false"), dhtFile: dht)
            .arguments(for: download, parentProcess: 42)
        #expect(arguments.first == download.torrentURL.path)
        #expect(arguments.contains("--select-file=3,2"))
        #expect(arguments.contains("--index-out=3=3.zip"))
        #expect(arguments.contains("--seed-time=0"))
        #expect(arguments.contains("--stop-with-process=42"))
        #expect(arguments.contains("--dht-file-path=\(dht.path)"))

        // A GameData zip already there is not downloaded again.
        let fm = FileManager.default
        try fm.createDirectory(
            at: download.items[1].destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: library.gameDataZip, to: download.items[1].destination)
        #expect(installer.downloadPlan(for: plan)?.items.count == 1)

        // Nothing to download once the archive is there.
        try fm.copyItem(at: library.gameZip, to: plan.archiveURL)
        let present = try #require(installer.plan(for: library.game))
        #expect(installer.downloadPlan(for: present) == nil)
    }

    @Test func downloadsThenInstallsWithExtras() async throws {
        let library = try await LiteLibrary()
        let installer = GameInstaller(snapshot: library.snapshot)
        let plan = try #require(installer.plan(for: library.game))
        let download = try #require(installer.downloadPlan(for: plan))
        let reports = Reports()
        try await TorrentDownloader(executable: library.fakeAria2()).download(download) { reports.add($0) }
        #expect(reports.all.count == 3)
        #expect(reports.all.contains { $0.fraction == 1 })
        let fm = FileManager.default
        for item in download.items { #expect(fm.fileExists(atPath: item.destination.path)) }
        #expect(!fm.fileExists(atPath: download.workDirectory.path))

        // Without a Mac setup record the plan would not unpack the GameData
        // zip; after the download it does, as eXo's script does.
        #expect(installer.plan(for: library.game)?.extrasArchiveURL == nil)
        let after = try #require(installer.plan(afterDownloading: download, for: library.game))
        #expect(after.extrasArchiveURL == download.items[1].destination)
        try await installer.install(after)
        #expect(fm.fileExists(atPath: after.installedFolderURL.appendingPathComponent("GAME.EXE").path))
        #expect(
            fm.fileExists(
                atPath: library.root.url.appendingPathComponent("eXo/eXoDOS/!dos/MiniGame/Extras/Map.txt").path))
    }

    @Test func reportsAFailedDownloadAndKeepsItsFiles() async throws {
        let library = try await LiteLibrary()
        let installer = GameInstaller(snapshot: library.snapshot)
        let plan = try #require(installer.plan(for: library.game))
        let download = try #require(installer.downloadPlan(for: plan))
        let downloader = TorrentDownloader(executable: try library.fakeAria2(status: 9))
        await #expect(throws: TorrentDownloadError.failed(status: 9, message: "CUID#7 - Not enough disk space.")) {
            try await downloader.download(download)
        }
        #expect(
            TorrentDownloadError.failed(status: 9, message: "").localizedDescription
                == "There is not enough disk space for the download.")
        // The scratch folder stays, so a later try resumes.
        #expect(FileManager.default.fileExists(atPath: download.scratchDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: download.items[0].destination.path))
    }

    /// Downloads ZZT's Revenge (0.2 MB, plus 1.8 MB of GameData) from the
    /// eXoDOS torrent in the mounted library: a real BitTorrent download.
    /// Run with `SILVERBOX_DOWNLOAD_SMOKE=1 swift test --filter DownloadTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SILVERBOX_DOWNLOAD_SMOKE"] == "1"))
    func downloadsFromTheEXoDOSTorrent() async throws {
        let torrentURL = try #require(RealLibrary.root.torrentURLs.first)
        let scratch = try FixtureLibrary.scratchDirectory()
        let downloader = try #require(
            TorrentDownloader.discover(dhtFile: scratch.appendingPathComponent("dht.dat")), "aria2c is not installed")
        let list = try TorrentFileList(contentsOf: torrentURL)
        let items = try ["eXo/eXoDOS/ZZT's Revenge! (1992).zip", "Content/GameData/eXoDOS/ZZT's Revenge! (1992).zip"]
            .map { path in
                DownloadPlan.Item(
                    file: try #require(list.file(at: path)), destination: scratch.appendingPathComponent(path))
            }
        let plan = DownloadPlan(
            torrentURL: torrentURL, items: items, workDirectory: scratch.appendingPathComponent("DOWNLOAD"),
            isWritable: true)
        let reports = Reports()
        let start = Date()
        try await downloader.download(plan) { reports.add($0) }
        for item in items {
            let size = try FileManager.default.attributesOfItem(atPath: item.destination.path)[.size] as? Int64
            #expect(size == item.file.length)
            let entries = try await ZipArchive.entries(of: item.destination)
            #expect(!entries.isEmpty)
        }
        let seconds = Int(Date().timeIntervalSince(start))
        print("Downloaded in \(seconds) s; peers at the end: \(reports.all.last?.connections ?? 0)")
    }
}

nonisolated private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [DownloadProgress] = []

    func add(_ report: DownloadProgress) {
        lock.lock()
        reports.append(report)
        lock.unlock()
    }

    var all: [DownloadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return reports
    }
}
