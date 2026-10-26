import SwiftUI
import SilverboxCore

/// A small capsule that states one fact, in a tone that says whether it is
/// fine, needs attention or is broken.
struct Chip: View {
    enum Tone { case neutral, good, warning, bad }

    var text: String
    var tone = Tone.neutral
    var systemImage: String?
    /// A small spinner in place of the image, for work under way.
    var isWorking = false
    /// The whole story, shown when the pointer rests on the chip: why
    /// something is missing, and what to do.
    var help: String?

    var body: some View {
        HStack(spacing: 4) {
            if isWorking {
                ProgressView().controlSize(.mini)
            } else if let systemImage {
                Image(systemName: systemImage).font(.caption2.bold())
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .help(help ?? "")
    }

    private var foreground: Color {
        switch tone {
        case .neutral: Theme.textPrimary
        case .good: Theme.good
        case .warning: Theme.warning
        case .bad: Theme.bad
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: Theme.textSecondary.opacity(0.15)
        case .good: Theme.good.opacity(0.14)
        case .warning: Theme.warning.opacity(0.16)
        case .bad: Theme.bad.opacity(0.14)
        }
    }
}

/// A row of chips that scrolls sideways instead of widening its container.
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { content }
        }
    }
}

/// What a game needs before it plays, and what it is: installed or not,
/// the emulator that will run it and whether that emulator is present, or
/// the kind of item it is when it is not a game to launch.
struct GameStatusChips: View {
    let game: Game
    @Environment(AppModel.self) private var model

    var body: some View {
        let chips = chips()
        if !chips.isEmpty {
            ChipRow {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in chip }
            }
        }
    }

    private func chips() -> [Chip] {
        var chips: [Chip] = []
        let installed = model.isInstalled(game)
        if game.isEXoGame, !model.isDocumentItem(game) {
            chips.append(
                installed
                    ? Chip(text: "Installed", tone: .good, systemImage: "checkmark.circle")
                    : Chip(text: "Not installed", systemImage: "square.and.arrow.down"))
        }
        switch game.launchKind {
        case .soundtrack: chips.append(Chip(text: "Soundtrack", systemImage: "music.note"))
        case .video: chips.append(Chip(text: "Video", systemImage: "film"))
        case .document: chips.append(Chip(text: "Document", systemImage: "doc.text"))
        case .link: chips.append(Chip(text: "Link", systemImage: "link"))
        case .emulator:
            let resolved = model.resolvedEmulator(for: game)
            chips.append(
                resolved.isReady
                    ? Chip(text: resolved.summary, tone: .good, systemImage: "cpu")
                    : Chip(
                        text: problemLabel(resolved), tone: .warning, systemImage: "exclamationmark.triangle",
                        help: resolved.problem))
        case .scummVM:
            if let installation = model.scummVMInstallation(for: game, variant: nil), installation.exists {
                chips.append(Chip(text: installation.kind.displayName, tone: .good, systemImage: "cpu"))
            } else {
                chips.append(
                    Chip(
                        text: "ScummVM missing", tone: .warning, systemImage: "exclamationmark.triangle",
                        help: Self.missingHelp(.scummVM)))
            }
        case .interactiveFiction:
            if installed {
                let variants = model.launchVariants(for: game)
                if let variant = model.preferredVariant(for: game, in: variants), let reason = variant.unsupportedReason
                {
                    chips.append(
                        Chip(
                            text: "Cannot start yet", tone: .warning, systemImage: "exclamationmark.triangle",
                            help: "\(variant.title): \(reason)."))
                } else {
                    chips.append(emulatorChip(model.emulatorKind(for: game)))
                }
            }
        case .windowsProgram:
            if game.eXoPack != nil {
                chips.append(
                    Chip(
                        text: "Cannot start on the Mac yet", tone: .warning, systemImage: "pc",
                        help:
                            "\(game.eXoPack?.displayName ?? "These") games need Windows programs that Silverbox cannot run yet."
                    ))
            }
        default:
            if game.isDOSGame || game.launchKind == .windows9x {
                chips.append(emulatorChip(model.emulatorKind(for: game)))
            }
        }
        if game.isEXoFavorite {
            chips.append(Chip(text: "eXo Favorite", systemImage: "star"))
        }
        return chips
    }

    /// The emulator by name, in good tone when its executable is present.
    private func emulatorChip(_ kind: EmulatorKind) -> Chip {
        if model.emulatorInstallation(kind)?.exists == true {
            return Chip(text: kind.displayName, tone: .good, systemImage: "cpu")
        }
        return Chip(
            text: "\(kind.displayName) missing", tone: .warning, systemImage: "exclamationmark.triangle",
            help: Self.missingHelp(kind))
    }

    /// A few words for a platform whose emulator cannot start the game; the
    /// chip's help has the whole reason.
    private func problemLabel(_ resolved: ResolvedEmulatorAssignment) -> String {
        guard let kind = resolved.assignment?.emulator else { return "No Mac emulator" }
        if model.emulatorInstallation(kind)?.exists != true { return "\(kind.displayName) missing" }
        return kind == .retroArch ? "RetroArch core missing" : "\(kind.displayName) not ready"
    }

    static func missingHelp(_ kind: EmulatorKind) -> String {
        "\(kind.displayName) is not installed. Get it from \(kind.website), or choose it in Settings › Emulators."
    }
}
