import Foundation

/// How far a download has come, from aria2's console readout. The totals
/// count whole torrent pieces (8 MB in eXoDOS's torrent), so they run over
/// the files' sizes, by far for a small game.
nonisolated public struct DownloadProgress: Sendable, Hashable {
    public var bytesDone: Int64
    public var bytesTotal: Int64
    public var bytesPerSecond: Int64
    /// Peers connected.
    public var connections: Int
    /// Connected peers that have the whole torrent.
    public var seeders: Int

    public init(bytesDone: Int64, bytesTotal: Int64, bytesPerSecond: Int64, connections: Int, seeders: Int) {
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
        self.bytesPerSecond = bytesPerSecond
        self.connections = connections
        self.seeders = seeders
    }

    /// 0 to 1, or nil while the total is unknown.
    public var fraction: Double? {
        bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : nil
    }

    /// Reads one readout line printed with `--human-readable=false`:
    /// `[#b15d3a 917504B/16777216B(5%) CN:3 SD:1 DL:466377B ETA:4s]`.
    public init?(readout line: String) {
        guard line.hasPrefix("[#"), line.hasSuffix("]") else { return nil }
        let fields = line.dropFirst().dropLast().split(separator: " ")
        guard fields.count >= 2 else { return nil }
        let amounts = fields[1].split(separator: "(")[0].split(separator: "/")
        guard amounts.count == 2, let done = Self.bytes(amounts[0]), let total = Self.bytes(amounts[1]) else {
            return nil
        }
        var values: [Substring: Substring] = [:]
        for field in fields.dropFirst(2) {
            let parts = field.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        self.init(
            bytesDone: done, bytesTotal: total, bytesPerSecond: values["DL"].flatMap(Self.bytes) ?? 0,
            connections: values["CN"].flatMap { Int($0) } ?? 0, seeders: values["SD"].flatMap { Int($0) } ?? 0)
    }

    private static func bytes(_ text: Substring) -> Int64? {
        Int64(text.hasSuffix("B") ? text.dropLast() : text)
    }
}

nonisolated public enum TorrentDownloadError: Error, Equatable {
    case noDownloader
    case readOnlyCollection
    case failed(status: Int32, message: String)
    case incomplete(String)
}

nonisolated extension TorrentDownloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noDownloader:
            return "Downloading needs aria2, which is not installed. Install it with Homebrew: brew install aria2."
        case .readOnlyCollection:
            return "The collection is read-only. Downloaded games go into the collection, as they do on Windows."
        case .failed(let status, let message):
            // aria2's exit codes, from its manual.
            switch status {
            case 9: return "There is not enough disk space for the download."
            case 15, 16: return "aria2 could not create the download's files. \(message)"
            default: return message.isEmpty ? "aria2 stopped with exit code \(status)." : message
            }
        case .incomplete(let name): return "The download ended, but \(name) is not complete."
        }
    }
}

/// Downloads files from an eXo torrent with aria2 (`aria2c`), an external
/// program, as eXo's own Lite script does on Windows. Like eXo, it stops
/// sharing as soon as the files are complete (`--seed-time=0`).
nonisolated public struct TorrentDownloader: Sendable, Hashable {
    public let executable: URL
    /// aria2's table of DHT nodes, kept between downloads. With it, aria2
    /// finds peers in seconds; without it, only through the torrent's
    /// trackers, many of which no longer answer, which can take minutes.
    public var dhtFile: URL?

    public init(executable: URL, dhtFile: URL? = nil) {
        self.executable = executable
        self.dhtFile = dhtFile
    }

    /// The node aria2 asks first when its DHT table is empty.
    static let dhtEntryPoint = "dht.transmissionbt.com:6881"

    /// Where Homebrew, MacPorts and Linux packages put `aria2c`. An app
    /// started from the Finder does not get the shell's PATH.
    public static let candidates = [
        "/opt/homebrew/bin/aria2c", "/usr/local/bin/aria2c", "/opt/local/bin/aria2c", "/usr/bin/aria2c",
    ].map { URL(fileURLWithPath: $0) }

    public static func discover(dhtFile: URL? = nil) -> TorrentDownloader? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }.map {
            TorrentDownloader(executable: $0, dhtFile: dhtFile)
        }
    }

    /// aria2's arguments for a plan. Each file is written under its torrent
    /// number in the scratch folder, so names with unusual characters need
    /// no escaping; aria2 also writes the parts of neighbouring files that
    /// share a piece with them, and removes those when it is done.
    public func arguments(for plan: DownloadPlan, parentProcess: Int32) -> [String] {
        var arguments = [
            plan.torrentURL.path,
            "--dir=\(plan.scratchDirectory.path)",
            "--select-file=\(plan.items.map { String($0.file.index) }.joined(separator: ","))",
        ]
        arguments += plan.items.map { "--index-out=\($0.file.index)=\(Self.scratchName(for: $0))" }
        arguments += [
            "--seed-time=0",
            "--file-allocation=none",
            "--bt-remove-unselected-file=true",
            "--auto-file-renaming=false",
            "--allow-overwrite=true",
            "--stop-with-process=\(parentProcess)",
            "--summary-interval=1",
            "--console-log-level=warn",
            "--human-readable=false",
            "--enable-color=false",
        ]
        if let dhtFile {
            arguments += ["--dht-file-path=\(dhtFile.path)", "--dht-entry-point=\(Self.dhtEntryPoint)"]
        }
        return arguments
    }

    static func scratchName(for item: DownloadPlan.Item) -> String { "\(item.file.index).zip" }

    /// Downloads the plan's files and moves each into the collection. A
    /// cancelled download keeps its scratch folder, and the next try
    /// resumes from it.
    public func download(_ plan: DownloadPlan, progress: (@Sendable (DownloadProgress) -> Void)? = nil)
        async throws
    {
        guard plan.isWritable else { throw TorrentDownloadError.readOnlyCollection }
        let scratch = plan.scratchDirectory
        let lease = try FileOperationCoordinator.shared.acquire(
            plan.items.map(\.destination) + [scratch], operation: "a game download")
        defer { lease.release() }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        if let dhtFile {
            try FileManager.default.createDirectory(
                at: dhtFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        try Task.checkCancellation()
        let lifecycle = CancellableProcess()
        let process = lifecycle.process
        process.executableURL = executable
        process.arguments = arguments(for: plan, parentProcess: ProcessInfo.processInfo.processIdentifier)
        process.currentDirectoryURL = scratch
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let output = ReadoutCollector()
        let report: @Sendable (Data) -> Void = { data in
            for line in output.lines(in: data) {
                if let report = DownloadProgress(readout: line) { progress?(report) }
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { report(data) }
        }
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak lifecycle] finished in
                    lifecycle?.finished()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    // The last lines can still be in the pipe; a newline ends one left open.
                    report(pipe.fileHandleForReading.readDataToEndOfFile() + Data("\n".utf8))
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try lifecycle.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            // aria2 saves its control file on SIGTERM, so the download resumes later.
            lifecycle.cancel()
        }
        try Task.checkCancellation()
        guard status == 0 else { throw TorrentDownloadError.failed(status: status, message: output.lastError) }

        let fm = FileManager.default
        for item in plan.items {
            let file = scratch.appendingPathComponent(Self.scratchName(for: item))
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? nil
            guard size == item.file.length else {
                throw TorrentDownloadError.incomplete(item.destination.lastPathComponent)
            }
            try fm.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: item.destination.path) { try fm.removeItem(at: item.destination) }
            try fm.moveItem(at: file, to: item.destination)
        }
        try? fm.removeItem(at: scratch)
        if (try? fm.contentsOfDirectory(atPath: plan.workDirectory.path))?.isEmpty == true {
            try? fm.removeItem(at: plan.workDirectory)
        }
    }
}

/// Splits aria2's output into lines and keeps its last error message.
nonisolated private final class ReadoutCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var partial = Data()
    private var error = ""

    func lines(in chunk: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        partial.append(chunk)
        var lines: [String] = []
        while let end = partial.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: partial[partial.startIndex..<end], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            partial.removeSubrange(partial.startIndex...end)
            // `10/26 11:30:00 [ERROR] CUID#7 - Download aborted.` and the like; the message is what follows.
            if let range = line.range(of: "[ERROR]") ?? line.range(of: "[WARN]") {
                error = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Exception:") {
                error = line
            }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    var lastError: String {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}
