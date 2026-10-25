import Foundation
import eXoCore

/// What `AppModel.checkEmulators()` found on this Mac: each emulator that is
/// present with its executable, the files in RetroArch's cores folder, and
/// whether DOSBox Staging has FluidSynth.
struct EmulatorCheck: Equatable {
    var executables: [EmulatorKind: String] = [:]
    var retroArchCores: [String] = []
    var fluidSynth = false

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
}
