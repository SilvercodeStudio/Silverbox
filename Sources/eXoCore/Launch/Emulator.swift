import Foundation

/// An emulator program Autoexec.Mac can start. DOSBox Staging and DOSBox-X run
/// eXoDOS games, DOSBox-X and 86Box run eXoWin9x games, and the others run
/// console, computer and arcade platforms from a LaunchBox library.
nonisolated public enum EmulatorKind: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case dosboxStaging
    case dosboxX
    case retroArch
    case dolphin
    case mame
    case mednafen
    case box86 = "86Box"
    case scummVM
    /// A second ScummVM, such as a daily build, for games whose engine the
    /// release build leaves out.
    case scummVMDaily
    case spatterlight

    public var id: String { rawValue }

    /// The emulators that run eXoDOS games.
    public static let dosBox: [EmulatorKind] = [.dosboxStaging, .dosboxX]
    /// The emulators that run ROMs and disc images from other platforms.
    public static let romEmulators: [EmulatorKind] = [.retroArch, .dolphin, .mame, .mednafen]

    public var isDOSBox: Bool { Self.dosBox.contains(self) }
    public var isScummVM: Bool { self == .scummVM || self == .scummVMDaily }

    public var displayName: String {
        switch self {
        case .dosboxStaging: return "DOSBox Staging"
        case .dosboxX: return "DOSBox-X"
        case .retroArch: return "RetroArch"
        case .dolphin: return "Dolphin"
        case .mame: return "MAME"
        case .mednafen: return "Mednafen"
        case .box86: return "86Box"
        case .scummVM: return "ScummVM"
        case .scummVMDaily: return "ScummVM daily build"
        case .spatterlight: return "Spatterlight"
        }
    }

    /// The executable's file name, also the name inside an `.app` bundle.
    public var executableName: String {
        switch self {
        case .dosboxStaging: return "dosbox"
        case .dosboxX: return "dosbox-x"
        case .retroArch: return "RetroArch"
        case .dolphin: return "Dolphin"
        case .mame: return "mame"
        case .mednafen: return "mednafen"
        case .box86: return "86Box"
        case .scummVM, .scummVMDaily: return "scummvm"
        case .spatterlight: return "Spatterlight"
        }
    }

    /// What the emulator is used for, shown in Settings.
    public var summary: String {
        switch self {
        case .dosboxStaging: return "Runs eXoDOS games set up for DOSBox 0.74, ECE and Staging."
        case .dosboxX: return "Runs eXoDOS games set up for DOSBox SVN Daum and DOSBox-X."
        case .retroArch: return "Runs most console and computer platforms through its libretro cores."
        case .dolphin: return "Runs Nintendo GameCube and Wii games."
        case .mame: return "Runs arcade ROM sets."
        case .mednafen: return "Runs several consoles from the command line, including Sega Saturn."
        case .box86:
            return "Runs the eXoWin9x games that need a full PC, such as a Pentium with a 3dfx Voodoo card."
        case .scummVM: return "Runs eXoScummVM games: LucasArts, Sierra and many other adventures."
        case .scummVMDaily:
            return "Runs the eXoScummVM games whose engine the release build of ScummVM leaves out."
        case .spatterlight:
            return
                "Plays eXoIF text adventures: Infocom and other Z-code, Glulx, TADS, Hugo, Level 9, Magnetic Scrolls and more."
        }
    }

    public var website: String {
        switch self {
        case .dosboxStaging: return "https://www.dosbox-staging.org"
        case .dosboxX: return "https://dosbox-x.com"
        case .retroArch: return "https://www.retroarch.com"
        case .dolphin: return "https://dolphin-emu.org"
        case .mame: return "https://www.mamedev.org"
        case .mednafen: return "https://mednafen.github.io"
        case .box86: return "https://86box.net"
        case .scummVM: return "https://www.scummvm.org"
        case .scummVMDaily: return "https://buildbot.scummvm.org"
        case .spatterlight: return "https://ccxvii.net/spatterlight/"
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
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: macOSDirectory, includingPropertiesForKeys: nil),
                let first = entries.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
            {
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
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: downloads, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            {
                for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
                where entry.lastPathComponent.lowercased().hasPrefix("dosbox-x") {
                    urls.append(entry.appendingPathComponent("dosbox-x-sdl2/dosbox-x.app/Contents/MacOS/dosbox-x"))
                    urls.append(entry.appendingPathComponent("dosbox-x/dosbox-x.app/Contents/MacOS/dosbox-x"))
                }
            }
        case .retroArch:
            urls += [
                URL(fileURLWithPath: "/Applications/RetroArch.app/Contents/MacOS/RetroArch"),
                home.appendingPathComponent("Applications/RetroArch.app/Contents/MacOS/RetroArch"),
                home.appendingPathComponent(
                    "Library/Application Support/Steam/steamapps/common/RetroArch/RetroArch.app/Contents/MacOS/RetroArch"
                ),
                URL(fileURLWithPath: "/opt/homebrew/bin/retroarch"),
                URL(fileURLWithPath: "/usr/local/bin/retroarch"),
            ]
        case .dolphin:
            urls += [
                URL(fileURLWithPath: "/Applications/Dolphin.app/Contents/MacOS/Dolphin"),
                home.appendingPathComponent("Applications/Dolphin.app/Contents/MacOS/Dolphin"),
                URL(fileURLWithPath: "/opt/homebrew/bin/dolphin-emu"),
                URL(fileURLWithPath: "/usr/local/bin/dolphin-emu"),
            ]
        case .mame:
            urls += [
                URL(fileURLWithPath: "/opt/homebrew/bin/mame"),
                URL(fileURLWithPath: "/usr/local/bin/mame"),
                URL(fileURLWithPath: "/Applications/MAME.app/Contents/MacOS/mame"),
                URL(fileURLWithPath: "/Applications/mame/mame"),
                home.appendingPathComponent("Applications/MAME.app/Contents/MacOS/mame"),
                home.appendingPathComponent("Applications/mame/mame"),
                home.appendingPathComponent("mame/mame"),
            ]
        case .mednafen:
            urls += [
                URL(fileURLWithPath: "/opt/homebrew/bin/mednafen"),
                URL(fileURLWithPath: "/usr/local/bin/mednafen"),
            ]
        case .box86:
            // The macOS download is a zip that holds only 86Box.app.
            urls += [
                URL(fileURLWithPath: "/Applications/86Box.app/Contents/MacOS/86Box"),
                home.appendingPathComponent("Applications/86Box.app/Contents/MacOS/86Box"),
                home.appendingPathComponent("Downloads/86Box.app/Contents/MacOS/86Box"),
            ]
        case .scummVM:
            urls += [
                URL(fileURLWithPath: "/Applications/ScummVM.app/Contents/MacOS/scummvm"),
                home.appendingPathComponent("Applications/ScummVM.app/Contents/MacOS/scummvm"),
                URL(fileURLWithPath: "/opt/homebrew/bin/scummvm"),
                URL(fileURLWithPath: "/usr/local/bin/scummvm"),
            ]
        case .scummVMDaily:
            // A daily build is a second ScummVM.app; it is chosen in Settings.
            break
        case .spatterlight:
            urls += [
                URL(fileURLWithPath: "/Applications/Spatterlight.app/Contents/MacOS/Spatterlight"),
                home.appendingPathComponent("Applications/Spatterlight.app/Contents/MacOS/Spatterlight"),
            ]
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
        case .retroArch, .dolphin, .mame, .mednafen, .box86, .scummVM, .scummVMDaily, .spatterlight:
            return false
        case .dosboxStaging:
            let fm = FileManager.default
            var folders = [
                "/opt/homebrew/lib", "/usr/local/lib", "/usr/lib", "/usr/lib/x86_64-linux-gnu",
                "/usr/lib/aarch64-linux-gnu",
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
