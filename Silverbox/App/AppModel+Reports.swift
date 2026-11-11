import Foundation
import SilverboxCore

extension AppModel {
    /// Help › Report a Problem…: a new GitHub issue's page, filled in with
    /// the version, the Mac, the collections and the emulators found. The
    /// user sends it, or not, in the browser.
    func problemReportURL() -> URL {
        ProblemReport.issueURL(
            ProblemReport.Details(
                program: AppInfo.versionLine, collections: collectionSummaries, emulators: emulatorSummaries))
    }

    /// Help › Send Feedback…: a new GitHub discussion, with only the version and the Mac.
    func feedbackURL() -> URL {
        ProblemReport.feedbackURL(program: AppInfo.versionLine)
    }

    /// "eXoDOS, eXoWin3x: 8,433 games" or "LaunchBox library: 35,028 games
    /// on 43 platforms". No names or paths: the user chose those.
    private var collectionSummaries: [String] {
        collections.map { collection in
            guard collection.isEnabled else { return "\(collection.kind.displayName): turned off" }
            guard let snapshot = library?.snapshot(id: collection.id) else {
                return "\(collection.kind.displayName): not loaded"
            }
            let present = Set(snapshot.games.compactMap(\.eXoPack))
            let packs = EXoPack.allCases.filter(present.contains).map(\.displayName)
            let games = "\(snapshot.games.count.formatted()) games"
            guard packs.isEmpty else { return "\(packs.joined(separator: ", ")): \(games)" }
            let platforms = Set(snapshot.games.map(\.platform)).count
            return "\(collection.kind.displayName): \(games) on \(platforms) platform\(platforms == 1 ? "" : "s")"
        }
    }

    /// The emulators found, with what each one has that matters: FluidSynth,
    /// RetroArch's cores, MAME's Apple IIGS ROM. Then aria2 for downloads.
    private var emulatorSummaries: [String] {
        let check = emulatorCheck
        var lines = EmulatorKind.allCases.filter { check.executables[$0] != nil }.map { kind in
            switch kind {
            case .dosboxStaging: return kind.displayName + (check.fluidSynth ? " (FluidSynth)" : " (no FluidSynth)")
            case .retroArch: return "\(kind.displayName) (\(check.retroArchCores.count) cores)"
            case .mame where check.appleIIGSROM: return "\(kind.displayName) (Apple IIGS ROM added)"
            default: return kind.displayName
            }
        }
        if check.downloader != nil { lines.append("aria2") }
        return lines
    }
}
