import Foundation

/// A game archive the collection lacks, and the torrent that has it. eXo's
/// Lite editions leave out every game zip and GameData zip; eXo's
/// `install.bat` downloads the two for a game from the full collection's
/// torrent in `eXo/util/aria/` with aria2, and so does Silverbox.
nonisolated public struct DownloadPlan: Sendable, Hashable {
    nonisolated public struct Item: Sendable, Hashable {
        public var file: TorrentFileList.File
        /// Where the file goes: the same path in the collection as in the torrent.
        public var destination: URL
    }

    public var torrentURL: URL
    /// The game's zip, then its GameData zip (manual, music, videos and
    /// extras) when the torrent has one and the collection does not.
    public var items: [Item]
    /// Where unfinished downloads wait, so a later try resumes:
    /// `eXo/DOWNLOAD/`, the folder eXo's script uses.
    public var workDirectory: URL
    /// False when the collection is read-only. Downloads go into the
    /// collection, as on Windows.
    public var isWritable: Bool

    public var gameBytes: Int64 { items.first?.file.length ?? 0 }
    public var extrasBytes: Int64 { items.dropFirst().reduce(0) { $0 + $1.file.length } }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.file.length } }

    /// This download's own folder in ``workDirectory``, named after the
    /// torrent and the file numbers so a later try finds it again.
    public var scratchDirectory: URL {
        let stem = torrentURL.deletingPathExtension().lastPathComponent
        let numbers = items.map { String($0.file.index) }.joined(separator: "-")
        return workDirectory.appendingPathComponent("\(stem)-\(numbers)", isDirectory: true)
    }
}

nonisolated extension LibraryRoot {
    /// eXo's torrents for on-demand downloads, `eXo/util/aria/*.torrent`,
    /// in the library and the download it was set up from.
    public var torrentURLs: [URL] {
        downloadRoots.flatMap { root -> [URL] in
            let folder = root.appendingPathComponent("eXo/util/aria", isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter { $0.lowercased().hasSuffix(".torrent") }.sorted()
                .map { folder.appendingPathComponent($0) }
        }
    }
}

nonisolated extension GameInstaller {
    /// How to get the archive a plan needs, or nil when it is present or no
    /// torrent of the collection lists it.
    public func downloadPlan(for plan: InstallPlan) -> DownloadPlan? {
        guard !plan.archiveExists, let pack = plan.game.eXoPack, let components = plan.game.installPathComponents
        else { return nil }
        let root = snapshot.root
        let name = plan.game.launcherBaseName
        let gamePath = "eXo/\(components.dropLast().joined(separator: "/"))/\(name).zip"
        let extrasPath = "Content/GameData/\(pack.directoryName)/\(name).zip"
        for torrent in root.torrentURLs {
            guard let list = TorrentFileList.cached(torrent), let game = list.file(at: gamePath) else { continue }
            var items = [DownloadPlan.Item(file: game, destination: plan.archiveURL)]
            let extras = root.downloadFile(extrasPath)
            if let file = list.file(at: extrasPath), !FileManager.default.fileExists(atPath: extras.path) {
                items.append(DownloadPlan.Item(file: file, destination: extras))
            }
            return DownloadPlan(
                torrentURL: torrent, items: items,
                workDirectory: root.eXoDirectory.appendingPathComponent("DOWNLOAD", isDirectory: true),
                isWritable: FileManager.default.isWritableFile(atPath: root.url.path))
        }
        return nil
    }

    /// The plan again after a download: the archive is now in place, and a
    /// GameData zip that the plan would not unpack (the setup unpacked the
    /// others, or ran on Windows) unpacks into the collection, as eXo's
    /// script does right after downloading it.
    public func plan(afterDownloading download: DownloadPlan, for game: Game) -> InstallPlan? {
        guard var plan = plan(for: game) else { return nil }
        if plan.extrasArchiveURL == nil, let extras = download.items.dropFirst().first?.destination,
            FileManager.default.fileExists(atPath: extras.path)
        {
            plan.extrasArchiveURL = extras
            plan.extrasDestination = snapshot.root.url
            plan.extrasPatterns = []
        }
        return plan
    }
}
