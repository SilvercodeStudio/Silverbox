import Foundation

/// The choices eXo's setup asks about that matter on the Mac. Display
/// choices are left out: Autoexec.Mac has its own launch options.
nonisolated public struct EXoSetupOptions: Hashable, Sendable, Codable {
    /// eXo asks whether to remove adult games (nudity) from the front end.
    /// They stay on disk either way; only the game list changes.
    public var includeAdultGames: Bool
    /// Unpack every game's manual, music, videos and extras now. When false,
    /// a game's extras are unpacked when the game is installed.
    public var unpackGameData: Bool
    /// Media add-ons to leave out, by archive name (`DOSMagazines.zip`).
    public var skippedAddOns: [String]

    public init(includeAdultGames: Bool = true, unpackGameData: Bool = false, skippedAddOns: [String] = []) {
        self.includeAdultGames = includeAdultGames
        self.unpackGameData = unpackGameData
        self.skippedAddOns = skippedAddOns
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeAdultGames = try c.decodeIfPresent(Bool.self, forKey: .includeAdultGames) ?? true
        unpackGameData = try c.decodeIfPresent(Bool.self, forKey: .unpackGameData) ?? false
        skippedAddOns = try c.decodeIfPresent([String].self, forKey: .skippedAddOns) ?? []
    }
}

/// What a setup did, kept in the set-up folder's `Data` folder.
nonisolated public struct EXoSetupRecord: Hashable, Sendable, Codable {
    public static let fileName = "Autoexec.Mac Setup.json"

    public var date: Date
    public var packs: [String]
    public var options: EXoSetupOptions
    /// The download the setup read, when it was not the set-up folder itself.
    public var downloadPath: String?

    public static func url(in root: URL) -> URL {
        root.appendingPathComponent("Data", isDirectory: true).appendingPathComponent(fileName)
    }

    public static func read(in root: URL) -> EXoSetupRecord? {
        guard let data = FileManager.default.contents(atPath: url(in: root).path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EXoSetupRecord.self, from: data)
    }

    func write(in root: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url(in: root), options: .atomic)
    }
}

nonisolated public struct EXoSetupProgress: Hashable, Sendable {
    public var stage: String
    public var detail: String?
    /// 0 to 1, over the whole setup.
    public var fraction: Double

    public init(stage: String, detail: String?, fraction: Double) {
        self.stage = stage
        self.detail = detail
        self.fraction = fraction
    }
}

/// Does what eXo's `Setup <pack>.bat` does, without Windows: unpacks the
/// packs' metadata, configs, add-ons, extras and tools, merges the LaunchBox
/// XML fragments into `Data`, and registers the add-on platforms.
///
/// `target` is the download itself for an in-place setup, or another folder
/// when the download cannot be written; game archives stay in the download.
nonisolated public struct EXoSetup: Sendable {
    public let download: EXoDownload
    public let target: URL
    public let options: EXoSetupOptions

    public init(download: EXoDownload, target: URL, options: EXoSetupOptions) {
        self.download = download
        self.target = target.standardizedFileURL
        self.options = options
    }

    nonisolated struct Step: Sendable {
        var title: String
        var archive: URL
        var destination: URL
        var excluded: [String] = []
        /// Count the files for a progress bar inside the step.
        var detailed = true
    }

    /// The add-ons the options keep.
    var addOns: [EXoDownload.AddOn] {
        download.addOns.filter { !options.skippedAddOns.contains($0.archive.lastPathComponent) }
    }

    /// The archives to unpack, in eXo's order. The nested util archives
    /// (`EXT*.zip`, `OPT*.zip`) come after, once util is unpacked.
    var steps: [Step] {
        let eXo = target.appendingPathComponent("eXo", isDirectory: true)
        var steps: [Step] = []
        for archive in download.metadataArchives {
            // LaunchBox plug-ins are of no use on the Mac.
            steps.append(
                Step(title: "Box art and game lists", archive: archive, destination: target, excluded: ["*.dll"]))
        }
        for addOn in addOns {
            steps.append(Step(title: "Media add-on", archive: addOn.archive, destination: target))
        }
        if options.unpackGameData {
            for archive in download.gameDataArchives {
                steps.append(Step(title: "Game extras", archive: archive, destination: target, detailed: false))
            }
        }
        for pack in download.packs {
            steps.append(
                Step(title: "\(pack.displayName) game configs", archive: pack.configArchive, destination: target))
        }
        for archive in download.utilArchives {
            steps.append(
                Step(
                    title: "Tools and emulator files", archive: archive,
                    destination: eXo.appendingPathComponent("util", isDirectory: true)))
        }
        return steps
    }

    public func run(progress: (@Sendable (EXoSetupProgress) -> Void)? = nil) async throws {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let steps = self.steps
        let weights = steps.map { Double(EXoDownload.size(of: [$0.archive])) }
        // The nested util archives and the XML merge get the last tenth.
        let total = max(1, weights.reduce(0, +) / 0.9)
        var done = 0.0
        for (step, weight) in zip(steps, weights) {
            try Task.checkCancellation()
            let start = done
            let report = { @Sendable (fraction: Double) in
                progress?(
                    EXoSetupProgress(
                        stage: step.title, detail: step.archive.lastPathComponent,
                        fraction: (start + weight * fraction) / total))
            }
            report(0)
            var onFile: (@Sendable (Int) -> Void)?
            if step.detailed {
                let entries = try await ZipArchive.entries(of: step.archive)
                let count = Double(max(1, entries.count))
                onFile = { files in report(min(1, Double(files) / count)) }
            }
            try await ZipArchive.extract(
                step.archive, into: step.destination, excluding: step.excluded, onFile: onFile)
            done += weight
        }

        progress?(EXoSetupProgress(stage: "Emulator files", detail: nil, fraction: 0.9))
        try await unpackNestedUtilArchives { fraction, name in
            progress?(EXoSetupProgress(stage: "Emulator files", detail: name, fraction: 0.9 + 0.08 * fraction))
        }

        progress?(EXoSetupProgress(stage: "Game lists", detail: nil, fraction: 0.98))
        try mergeXML()
        try registerAddOns()
        let downloadPath = download.root.standardizedFileURL == target ? nil : download.root.path
        try EXoSetupRecord(
            date: Date(), packs: download.packs.map(\.name), options: options, downloadPath: downloadPath
        ).write(in: target)
        progress?(EXoSetupProgress(stage: "Done", detail: nil, fraction: 1))
    }

    /// util*.zip holds `EXT<pack>.zip` (emulators, MT-32 files and updates,
    /// unpacked into `eXo`) and `OPT<pack>.zip` (optional Windows tools,
    /// unpacked into `eXo/util`). eXo's setup deletes them afterwards; the
    /// util zip still holds them.
    func unpackNestedUtilArchives(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let fm = FileManager.default
        let eXo = target.appendingPathComponent("eXo", isDirectory: true)
        let util = eXo.appendingPathComponent("util", isDirectory: true)
        let names = ((try? fm.contentsOfDirectory(atPath: util.path)) ?? []).sorted()
        let nested = names.filter {
            let lowered = $0.lowercased()
            return lowered.hasSuffix(".zip") && (lowered.hasPrefix("ext") || lowered.hasPrefix("opt"))
        }
        for (index, name) in nested.enumerated() {
            try Task.checkCancellation()
            let archive = util.appendingPathComponent(name)
            let destination = name.lowercased().hasPrefix("ext") ? eXo : util
            let count = max(1, (try? await ZipArchive.entries(of: archive).count) ?? 1)
            let share = 1 / Double(nested.count)
            try await ZipArchive.extract(archive, into: destination) { files in
                progress((Double(index) + min(1, Double(files) / Double(count))) * share, name)
            }
            try fm.removeItem(at: archive)
        }
        let deprotect = util.appendingPathComponent("deprotect.zip")
        if fm.fileExists(atPath: deprotect.path) { try fm.removeItem(at: deprotect) }
    }

    // MARK: - LaunchBox XML

    /// eXo ships each platform's game list as fragments in `xml/` and joins
    /// them with small batch files such as `merge_platforms.bat`:
    ///
    ///     echo ^<?xml version="1.0" standalone="yes"?^> > Platforms.xml
    ///     echo ^<LaunchBox^> >> Platforms.xml
    ///     type .\platforms\*.platforms >> Platforms.xml
    ///
    /// This reads each batch file for its output name and fragment pattern
    /// and joins the fragments the same way. Lists in `xml/all` include adult
    /// games; `xml/family` leaves them out.
    func mergeXML() throws {
        let fm = FileManager.default
        let xml = target.appendingPathComponent("xml", isDirectory: true)
        let data = target.appendingPathComponent("Data", isDirectory: true)
        let platforms = data.appendingPathComponent("Platforms", isDirectory: true)
        let playlists = data.appendingPathComponent("Playlists", isDirectory: true)
        try fm.createDirectory(at: platforms, withIntermediateDirectories: true)
        try fm.createDirectory(at: playlists, withIntermediateDirectories: true)
        let listFolder = options.includeAdultGames ? "all" : "family"

        // Whole platform files, such as MS-DOS.xml, and the playlists.
        if let folder = Self.subfolder(of: xml, named: listFolder) {
            try copyFiles(in: folder, withExtension: "xml", to: platforms)
        }
        if let folder = Self.subfolder(of: xml, named: "Playlists") {
            try copyFiles(in: folder, withExtension: nil, to: playlists)
        }

        let scripts = ((try? fm.contentsOfDirectory(atPath: xml.path)) ?? []).sorted()
            .filter { $0.lowercased().hasPrefix("merge_") && $0.lowercased().hasSuffix(".bat") }
        for name in scripts {
            let script = String(decoding: try Data(contentsOf: xml.appendingPathComponent(name)), as: UTF8.self)
            guard let merge = Self.mergeCommand(in: script) else { continue }
            let lowered = merge.folder.lowercased()
            if lowered == "all" || lowered == "family", lowered != listFolder { continue }
            guard let folder = Self.subfolder(of: xml, named: merge.folder) else { continue }
            let fragments = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
                .filter { ($0 as NSString).pathExtension.caseInsensitiveCompare(merge.fileExtension) == .orderedSame }
            var text = "<?xml version=\"1.0\" standalone=\"yes\"?>\n<LaunchBox>\n"
            for fragment in fragments {
                var part = String(
                    decoding: try Data(contentsOf: folder.appendingPathComponent(fragment)), as: UTF8.self)
                if part.hasPrefix("\u{FEFF}") { part.removeFirst() }
                text += part
                if !text.hasSuffix("\n") { text += "\n" }
            }
            text += "</LaunchBox>\n"
            // eXo copies Platforms.xml and Parents.xml to Data, and the other
            // merged lists (such as "Windows 9x.xml") to Data/Platforms.
            let isDataFile = ["platforms.xml", "parents.xml"].contains(merge.output.lowercased())
            let destination = (isDataFile ? data : platforms).appendingPathComponent(merge.output)
            try text.write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    /// The output file and fragment pattern of one merge batch file.
    static func mergeCommand(in script: String) -> (output: String, folder: String, fileExtension: String)? {
        var output: String?
        var folder: String?
        var fileExtension: String?
        for raw in script.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if output == nil, line.lowercased().hasPrefix("echo"), !line.contains(">>"),
                let match = line.firstMatch(of: /> *"?([^">]+?)"? *$/)
            {
                output = String(match.1)
            }
            if let match = line.firstMatch(of: /(?i)^type +\.?\\?([^\\ ]+)\\\*\.([A-Za-z0-9]+)/) {
                folder = String(match.1)
                fileExtension = String(match.2)
            }
        }
        guard let output, let folder, let fileExtension else { return nil }
        return (output, folder, fileExtension)
    }

    /// Adds each add-on platform to `Data/Platforms.xml` and files it under
    /// its category in `Data/Parents.xml`, as eXo's `eXoLBpm.exe` does.
    func registerAddOns() throws {
        let addOns = self.addOns
        guard !addOns.isEmpty else { return }
        let data = target.appendingPathComponent("Data", isDirectory: true)
        let platformsFile = data.appendingPathComponent("Platforms.xml")
        let parentsFile = data.appendingPathComponent("Parents.xml")
        var platforms = (try? String(contentsOf: platformsFile, encoding: .utf8)) ?? Self.emptyList
        var parents = (try? String(contentsOf: parentsFile, encoding: .utf8)) ?? Self.emptyList
        for addOn in addOns {
            let category = Self.escape(addOn.category)
            if !platforms.contains("<Name>\(category)</Name>") {
                platforms = Self.inserting(
                    "  <PlatformCategory>\n    <Name>\(category)</Name>\n    <NestedName>\(category)</NestedName>\n  </PlatformCategory>\n",
                    into: platforms)
            }
            for name in addOn.platforms.map(Self.escape) {
                if platforms.range(
                    of: "<Platform>\\s*<Name>\(NSRegularExpression.escapedPattern(for: name))</Name>",
                    options: .regularExpression) == nil
                {
                    platforms = Self.inserting(
                        "  <Platform>\n    <Name>\(name)</Name>\n  </Platform>\n", into: platforms)
                }
                if !parents.contains("<PlatformName>\(name)</PlatformName>") {
                    parents = Self.inserting(
                        "  <Parent>\n    <PlatformName>\(name)</PlatformName>\n    <ParentPlatformCategoryName>\(category)</ParentPlatformCategoryName>\n  </Parent>\n",
                        into: parents)
                }
            }
        }
        try platforms.write(to: platformsFile, atomically: true, encoding: .utf8)
        try parents.write(to: parentsFile, atomically: true, encoding: .utf8)
    }

    static let emptyList = "<?xml version=\"1.0\" standalone=\"yes\"?>\n<LaunchBox>\n</LaunchBox>\n"

    static func inserting(_ element: String, into document: String) -> String {
        guard let end = document.range(of: "</LaunchBox>", options: .backwards) else { return document + element }
        var result = document
        result.insert(contentsOf: element, at: end.lowerBound)
        return result
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Finds `name` in `folder` whatever its case: eXo writes `ALL` and `all`.
    static func subfolder(of folder: URL, named name: String) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries.first { $0.caseInsensitiveCompare(name) == .orderedSame }
            .map { folder.appendingPathComponent($0, isDirectory: true) }
    }

    private func copyFiles(in folder: URL, withExtension fileExtension: String?, to destination: URL) throws {
        let fm = FileManager.default
        for name in ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []) {
            let source = folder.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if let fileExtension, (name as NSString).pathExtension.caseInsensitiveCompare(fileExtension) != .orderedSame
            {
                continue
            }
            let target = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: source, to: target)
        }
    }
}
