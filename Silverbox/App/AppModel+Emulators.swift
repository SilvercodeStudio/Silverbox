import Foundation
import SilverboxCore

/// What `AppModel.checkEmulators()` found on this Mac: each emulator that is
/// present with its executable, the files in RetroArch's cores folder,
/// whether DOSBox Staging has FluidSynth, aria2 for game downloads, and
/// the Apple IIGS ROM that MAME needs for some eXoAppleIIGS games.
struct EmulatorCheck: Equatable {
    var executables: [EmulatorKind: String] = [:]
    var retroArchCores: [String] = []
    var fluidSynth = false
    var downloader: TorrentDownloader?
    var appleIIGSROM = false

    init() {}

    init(_ settings: AppSettings) {
        for kind in EmulatorKind.allCases {
            if let installation = settings.emulatorInstallation(kind), installation.exists {
                executables[kind] = installation.executableURL.path
            }
        }
        if let cores = settings.retroArchSetup?.coresDirectory {
            retroArchCores = (try? FileManager.default.contentsOfDirectory(atPath: cores.path).sorted()) ?? []
        }
        fluidSynth =
            settings.emulatorInstallation(.dosboxStaging).map(EmulatorCapabilities.fluidSynthAvailable) ?? false
        downloader = TorrentDownloader.discover(dhtFile: AppPaths.torrentState.appendingPathComponent("dht.dat"))
        appleIIGSROM = FileManager.default.fileExists(
            atPath: AppleIIGSCharacterROM.url(inMAMEDirectory: settings.localStore.mameDirectory).path)
    }
}

extension AppModel {
    /// Looks for the emulators again. The model does this when the app comes
    /// to the front; Settings and the welcome view also do it every few
    /// seconds while they are open, so an emulator installed meanwhile shows.
    func checkEmulators() {
        let check = EmulatorCheck(settings)
        if check != emulatorCheck { emulatorCheck = check }
    }

    /// `settings.emulatorInstallation(_:)` for views. It reads
    /// `emulatorCheck`, so a view that shows the result redraws when
    /// `checkEmulators()` finds a change.
    func emulatorInstallation(_ kind: EmulatorKind) -> EmulatorInstallation? {
        _ = emulatorCheck
        return settings.emulatorInstallation(kind)
    }

    /// `settings.retroArchSetup` for views, followed as `emulatorInstallation(_:)` is.
    var retroArchSetup: RetroArchSetup? {
        _ = emulatorCheck
        return settings.retroArchSetup
    }

    /// Whether DOSBox Staging can play General MIDI through FluidSynth.
    var fluidSynthAvailable: Bool { emulatorCheck.fluidSynth }

    /// aria2, which downloads the games a Lite collection leaves out.
    var torrentDownloader: TorrentDownloader? { emulatorCheck.downloader }

    /// Whether the user has added the Apple IIGS character ROM for MAME.
    var hasAppleIIGSROM: Bool { emulatorCheck.appleIIGSROM }

    /// Why an eXoAppleIIGS game cannot start, or nil. Follows the check, so
    /// views redraw when the ROM is added.
    func appleIIGSProblem(for game: Game) -> String? {
        _ = emulatorCheck
        guard let snapshot = snapshot(for: game) else { return nil }
        return launchPlanner(snapshot).appleIIGSProblem(for: game)
    }

    /// Checks a file the user chose, the ROM or a zip that holds it, and
    /// keeps a copy in the local data folder's MAME folder.
    func importAppleIIGSROM(from url: URL) {
        let destination = AppleIIGSCharacterROM.url(inMAMEDirectory: localStore.mameDirectory)
        Task {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                try await AppleIIGSCharacterROM.importFile(from: url, to: destination)
                checkEmulators()
            } catch {
                alert = AppAlert(title: "Not the Apple IIGS ROM", message: error.localizedDescription)
            }
        }
    }
}
