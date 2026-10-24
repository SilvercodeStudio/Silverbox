import Foundation

/// A file written before launch with text the planner changed: a game's
/// batch file with a setting the emulator would not accept.
nonisolated public struct FilePatch: Hashable, Sendable {
    public var destination: URL
    /// The whole file. Batch files are read and written as Latin-1 so that
    /// their DOS code-page bytes survive the round trip.
    public var text: String

    public init(destination: URL, text: String) {
        self.destination = destination
        self.text = text
    }

    public func write() throws {
        let fm = FileManager.default
        if let existing = fm.contents(atPath: destination.path),
            String(data: existing, encoding: .isoLatin1) == text
        {
            return
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (text.data(using: .isoLatin1) ?? Data(text.utf8)).write(to: destination, options: [.atomic])
    }
}

/// eXo's in-game menus switch the MIDI device while the emulator runs,
/// with `CONFIG -set "mididevice=default"` for General MIDI. DOSBox Staging
/// no longer knows `default`, so the choice falls through to CoreMIDI
/// whatever the launch options chose. This rewrites that line to the device
/// the translation uses, and keeps a note of the original so a later launch
/// with another choice can rewrite it again.
nonisolated public enum MIDIBatchPatcher {
    static let marker = "rem Autoexec.Mac replaced: "

    /// The patched batch files under `gameFolder`, two levels deep, with
    /// each one's destination: in place, or the same relative path under
    /// the overlay folder when the game sits on a read-only library.
    public static func patches(gameFolder: URL, overlay: OverlayMount?, device: String) -> [FilePatch] {
        var patches: [FilePatch] = []
        for file in batchFiles(in: gameFolder) {
            guard let data = FileManager.default.contents(atPath: file.path) else { continue }
            guard let text = String(data: data, encoding: .isoLatin1) else { continue }
            guard let rewritten = rewrite(text, device: device) else { continue }
            patches.append(FilePatch(destination: destination(for: file, overlay: overlay), text: rewritten))
        }
        return patches.sorted { $0.destination.path < $1.destination.path }
    }

    /// The text with every `mididevice=default` line replaced, or nil when
    /// there is nothing to change. Already replaced lines follow the device
    /// chosen now.
    public static func rewrite(_ text: String, device: String) -> String? {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: newline)
        var changed = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix(marker.lowercased()) {
                // Our own earlier replacement: the next line carries the device.
                let replacement = indent + "CONFIG -set \"mididevice=\(device)\""
                if index + 1 < lines.count, lines[index + 1] != replacement {
                    lines[index + 1] = replacement
                    changed = true
                }
                index += 2
                continue
            }
            if Self.setsDefaultDevice(trimmed) {
                lines.replaceSubrange(
                    index...index, with: [indent + marker + trimmed, indent + "CONFIG -set \"mididevice=\(device)\""])
                changed = true
                index += 2
                continue
            }
            index += 1
        }
        return changed ? lines.joined(separator: newline) : nil
    }

    /// `CONFIG -set "mididevice=default"`, with or without the quotes, in any case.
    static func setsDefaultDevice(_ line: String) -> Bool {
        let folded = line.lowercased().replacingOccurrences(of: "\"", with: "")
        let parts = folded.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return parts.count == 3 && parts[0] == "config" && parts[1] == "-set" && parts[2] == "mididevice=default"
    }

    private static func batchFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        guard let top = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        for entry in top {
            if entry.pathExtension.lowercased() == "bat" {
                files.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                let inner = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
            {
                files.append(contentsOf: inner.filter { $0.pathExtension.lowercased() == "bat" })
            }
        }
        return files
    }

    private static func destination(for file: URL, overlay: OverlayMount?) -> URL {
        guard let overlay else { return file }
        let base = overlay.base.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return file }
        return overlay.directory.appendingPathComponent(String(path.dropFirst(base.count + 1)))
    }
}
