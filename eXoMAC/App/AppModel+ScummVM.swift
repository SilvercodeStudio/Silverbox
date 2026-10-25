import Foundation
import eXoCore

/// eXoScummVM games: which ScummVM runs them, and the choices eXo's
/// launcher asks for.
extension AppModel {
    /// The games a ScummVM executable can run, from `--list-games`, read
    /// once per executable.
    func scummVMGames(_ installation: EmulatorInstallation) -> ScummVMGames? {
        let path = installation.executableURL.path
        if let known = scummVMGameCache[path] { return known }
        let process = Process()
        process.executableURL = installation.executableURL
        // A config file of our own, so ScummVM does not create its default one.
        process.arguments = ["--config=\(localStore.scummVMConfigURL.path)", "--list-games"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try FileManager.default.createDirectory(
                at: localStore.scummVMConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let games = ScummVMGames(listGamesOutput: String(decoding: data, as: UTF8.self))
        guard !games.ids.isEmpty else { return nil }
        scummVMGameCache[path] = games
        return games
    }

    private func scummVMGameID(for game: Game, variant: LaunchVariant?) -> String? {
        snapshot(for: game).flatMap {
            launchPlanner($0).scummVMGameID(
                for: game, variant: variant)
        }
    }

    /// The ScummVM that can run the game: the release build, else the daily
    /// build when one is set and has it. The release build when neither does.
    func scummVMInstallation(for game: Game, variant: LaunchVariant?) -> EmulatorInstallation? {
        _ = emulatorCheck
        guard let release = settings.emulatorInstallation(.scummVM), release.exists else {
            return settings.emulatorInstallation(.scummVMDaily)
        }
        guard let id = scummVMGameID(for: game, variant: variant), scummVMGames(release)?.supports(id) == false
        else { return release }
        if let daily = settings.emulatorInstallation(.scummVMDaily), daily.exists,
            scummVMGames(daily)?.supports(id) == true
        {
            return daily
        }
        return release
    }

    /// An alert when the chosen ScummVM cannot run the game.
    func scummVMEngineProblem(_ game: Game, variant: LaunchVariant?, emulator: EmulatorInstallation) -> AppAlert? {
        guard let id = scummVMGameID(for: game, variant: variant), scummVMGames(emulator)?.supports(id) == false
        else { return nil }
        return AppAlert(
            title: "ScummVM cannot run \(game.title)",
            message:
                "This ScummVM does not include the game “\(id)”. Release builds leave out engines and games that are not finished; a daily build from buildbot.scummvm.org has them. Choose one in Settings › Emulators › ScummVM daily build."
        )
    }
}

extension AppModel {
    private func planner(for game: Game) -> LaunchPlanner? {
        snapshot(for: game).map { launchPlanner($0) }
    }

    /// The variant's music devices, subtitle option and the like.
    func scummVMFiles(for variant: LaunchVariant) -> ScummVMVariantFiles {
        ScummVMVariantFiles(folder: variant.configURL)
    }

    /// eXo's note for the game, shown before it starts.
    func scummVMNote(for game: Game, variant: LaunchVariant?) -> String? {
        planner(for: game)?.scummVMNote(for: game, variant: variant)
    }

    /// The ScummVM version eXo runs the game with, such as `2.9.0`.
    func scummVMVersion(for game: Game, variants: [LaunchVariant], variant: LaunchVariant?) -> String? {
        guard let entry = planner(for: game)?.scummVMEntry(for: game, variant: variant, variantCount: variants.count)
        else { return nil }
        if !entry.versionFolder.isEmpty { return entry.versionFolder }
        let ini = planner(for: game)?.scummVMDirectory.appendingPathComponent("scummvm.ini")
        return ini.flatMap { FileManager.default.contents(atPath: $0.path) }
            .flatMap { ScummVMSettings.parse(String(decoding: $0, as: UTF8.self)).value("scummvm", "versioninfo") }
    }
}
