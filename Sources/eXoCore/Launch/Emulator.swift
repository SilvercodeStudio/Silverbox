import Foundation

nonisolated public enum EmulatorKind: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case dosboxStaging
    case dosboxX

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dosboxStaging: return "DOSBox Staging"
        case .dosboxX: return "DOSBox-X"
        }
    }

    public var executableName: String {
        switch self {
        case .dosboxStaging: return "dosbox"
        case .dosboxX: return "dosbox-x"
        }
    }
}

/// A usable emulator: which one it is and where its executable lives.
nonisolated public struct EmulatorInstallation: Hashable, Sendable, Codable, Identifiable {
    public var kind: EmulatorKind
    public var executableURL: URL

    public var id: String { "\(kind.rawValue):\(executableURL.path)" }

    public init(kind: EmulatorKind, executableURL: URL) {
        self.kind = kind
        self.executableURL = executableURL
    }

    public var exists: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    /// The `.app` bundle that holds the executable, when there is one.
    public var appBundleURL: URL? {
        var url = executableURL
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { return url }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    /// Accepts either an executable or an `.app` bundle and returns the
    /// executable inside it.
    public static func resolveExecutable(from url: URL, kind: EmulatorKind) -> URL {
        if url.pathExtension == "app" {
            let macOSDirectory = url.appendingPathComponent("Contents/MacOS", isDirectory: true)
            let preferred = macOSDirectory.appendingPathComponent(kind.executableName)
            if FileManager.default.isExecutableFile(atPath: preferred.path) { return preferred }
            if let entries = try? FileManager.default.contentsOfDirectory(at: macOSDirectory, includingPropertiesForKeys: nil),
               let first = entries.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
                return first
            }
            return preferred
        }
        return url
    }
}

/// Finds emulators in their usual places.
nonisolated public enum EmulatorLocator {
    public static func candidates(for kind: EmulatorKind) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls: [URL] = []
        switch kind {
        case .dosboxStaging:
            urls += [
                URL(fileURLWithPath: "/Applications/DOSBox Staging.app/Contents/MacOS/dosbox"),
                home.appendingPathComponent("Applications/DOSBox Staging.app/Contents/MacOS/dosbox"),
                URL(fileURLWithPath: "/opt/homebrew/bin/dosbox-staging"),
                URL(fileURLWithPath: "/usr/local/bin/dosbox-staging"),
                URL(fileURLWithPath: "/usr/bin/dosbox-staging"),
            ]
        case .dosboxX:
            urls += [
                URL(fileURLWithPath: "/Applications/dosbox-x.app/Contents/MacOS/dosbox-x"),
                URL(fileURLWithPath: "/Applications/DOSBox-X.app/Contents/MacOS/dosbox-x"),
                home.appendingPathComponent("Applications/dosbox-x.app/Contents/MacOS/dosbox-x"),
                URL(fileURLWithPath: "/opt/homebrew/bin/dosbox-x"),
                URL(fileURLWithPath: "/usr/local/bin/dosbox-x"),
                URL(fileURLWithPath: "/usr/bin/dosbox-x"),
            ]
            // The official macOS zip unpacks to a folder with SDL1 and SDL2 apps.
            let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
            if let entries = try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) where entry.lastPathComponent.lowercased().hasPrefix("dosbox-x") {
                    urls.append(entry.appendingPathComponent("dosbox-x-sdl2/dosbox-x.app/Contents/MacOS/dosbox-x"))
                    urls.append(entry.appendingPathComponent("dosbox-x/dosbox-x.app/Contents/MacOS/dosbox-x"))
                }
            }
        }
        return urls
    }

    public static func discover(_ kind: EmulatorKind) -> EmulatorInstallation? {
        for url in candidates(for: kind) where FileManager.default.isExecutableFile(atPath: url.path) {
            return EmulatorInstallation(kind: kind, executableURL: url)
        }
        return nil
    }
}

/// What an installed emulator can do on this machine.
nonisolated public enum EmulatorCapabilities {
    /// DOSBox Staging loads FluidSynth dynamically, so General MIDI through
    /// FluidSynth only works when the library is installed (for example with
    /// Homebrew). DOSBox-X builds it in.
    public static func fluidSynthAvailable(for installation: EmulatorInstallation) -> Bool {
        switch installation.kind {
        case .dosboxX:
            return true
        case .dosboxStaging:
            let fm = FileManager.default
            var folders = [
                "/opt/homebrew/lib", "/usr/local/lib", "/usr/lib", "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu",
            ].map { URL(fileURLWithPath: $0, isDirectory: true) }
            if let bundle = installation.appBundleURL {
                folders.insert(bundle.appendingPathComponent("Contents/MacOS/lib", isDirectory: true), at: 0)
                folders.insert(bundle.appendingPathComponent("Contents/Frameworks", isDirectory: true), at: 0)
            }
            for folder in folders {
                guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
                if entries.contains(where: { $0.lowercased().hasPrefix("libfluidsynth") }) { return true }
            }
            return false
        }
    }
}
