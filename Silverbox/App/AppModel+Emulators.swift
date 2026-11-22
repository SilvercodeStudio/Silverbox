import AppKit
import Foundation
import SilverboxCore

/// What `AppModel.checkEmulators()` found on this Mac: each emulator that is
/// present with its executable, the files in RetroArch's cores folder,
/// whether DOSBox Staging has FluidSynth, aria2 for game downloads, the
/// Apple IIGS ROM that MAME needs for some eXoAppleIIGS games, and the
/// emulators that macOS will stop until the user allows them.
struct EmulatorCheck: Equatable {
    var executables: [EmulatorKind: String] = [:]
    /// Present, but macOS will refuse to start it: a download that Apple has
    /// not notarized and the user has not allowed yet (`Gatekeeper`).
    var blocked: Set<EmulatorKind> = []
    /// Marked as a download and not asked about yet; `checkEmulators()` asks.
    var unassessed: [EmulatorKind: URL] = [:]
    var retroArchCores: [String] = []
    var fluidSynth = false
    var downloader: TorrentDownloader?
    var appleIIGSROM = false

    init() {}

    init(_ settings: AppSettings) {
        for kind in EmulatorKind.allCases {
            if let installation = settings.emulatorInstallation(kind), installation.exists {
                executables[kind] = installation.executableURL.path
                switch Gatekeeper.quickVerdict(app: installation.gatekeeperTarget) {
                case .allowed: break
                case .blocked: blocked.insert(kind)
                case .unknown: unassessed[kind] = installation.gatekeeperTarget
                }
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
        // macOS's assessment reads the whole app, so it runs off the main thread, once for
        // each download that is not allowed yet; the answer is kept, and the next check has it.
        let unassessed = Array(check.unassessed.values)
        guard !unassessed.isEmpty, !isAssessingEmulators else { return }
        isAssessingEmulators = true
        Task {
            await Task.detached { for app in unassessed { _ = Gatekeeper.isBlocked(app: app) } }.value
            isAssessingEmulators = false
            checkEmulators()
        }
    }

    /// True for an emulator that is installed but that macOS will stop at
    /// its start, until the user allows it in System Settings.
    func isBlockedByMacOS(_ kind: EmulatorKind) -> Bool { emulatorCheck.blocked.contains(kind) }

    /// What to do about an emulator that macOS stops, for help tags.
    static func blockedHelp(_ kind: EmulatorKind) -> String {
        "Apple has not checked \(kind.displayName), so macOS stops it the first time it starts. Allow it once: Settings › Emulators shows how."
    }

    /// Opens the emulator by itself. macOS then shows its warning, and after
    /// it the Open Anyway button in System Settings › Privacy & Security.
    func openEmulatorOnce(_ kind: EmulatorKind) {
        guard let installation = emulatorInstallation(kind) else { return }
        NSWorkspace.shared.openApplication(
            at: installation.gatekeeperTarget, configuration: NSWorkspace.OpenConfiguration())
    }

    /// System Settings › Privacy & Security, where Open Anyway is.
    func openPrivacyAndSecurity() {
        for address in [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security",
            "x-apple.systempreferences:com.apple.preference.security?General",
        ] {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
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
