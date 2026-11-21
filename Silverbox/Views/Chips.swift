import SwiftUI
import SilverboxCore

/// Whether a thing is fine, needs attention or is broken.
enum StatusTone {
    case neutral, good, warning, bad

    var color: Color {
        switch self {
        case .neutral: Theme.textSecondary
        case .good: Theme.good
        case .warning: Theme.warning
        case .bad: Theme.bad
        }
    }

    /// The glyph that says the same as the colour, for a status line.
    var systemImage: String {
        switch self {
        case .neutral: "circle"
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .bad: "xmark.circle.fill"
        }
    }
}

/// A tone's glyph in its colour. The warning triangle has a dark "!" on
/// its yellow, so that it reads on a light window too.
struct StatusGlyph: View {
    var tone: StatusTone
    /// Another glyph than the tone's own.
    var systemImage: String?

    var body: some View {
        let name = systemImage ?? tone.systemImage
        if name == "exclamationmark.triangle.fill" {
            Image(systemName: name)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Theme.warningMark, tone == .warning ? Theme.warning : tone.color)
        } else {
            Image(systemName: name).foregroundStyle(tone.color)
        }
    }
}

/// One line of status: a glyph in the tone's colour, and the text in a text
/// colour. The accent is for actions and selection, so status never takes it.
struct StatusLabel: View {
    var text: String
    var tone: StatusTone
    /// Another glyph than the tone's own.
    var systemImage: String?
    var textStyle = Theme.textPrimary

    init(_ text: String, tone: StatusTone, systemImage: String? = nil, textStyle: Color = Theme.textPrimary) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
        self.textStyle = textStyle
    }

    var body: some View {
        // Not a Label: a form gives a label's icon a wide column of its own.
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            StatusGlyph(tone: tone, systemImage: systemImage)
            Text(text).foregroundStyle(textStyle).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small capsule that states one fact, in a tone that says whether it is
/// fine, needs attention or is broken. The tone colours the glyph and the
/// fill; the text stays in the text colour.
struct Chip: View {
    typealias Tone = StatusTone

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
                Group {
                    if tone == .neutral {
                        Image(systemName: systemImage).foregroundStyle(Theme.textPrimary)
                    } else {
                        StatusGlyph(tone: tone, systemImage: systemImage)
                    }
                }
                .font(.caption2.bold())
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(tone.color.opacity(tone == .neutral ? 0.15 : 0.16), in: Capsule())
        .help(help ?? "")
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

/// What a game needs before it plays, and what it is: installed,
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
        // A game that is not installed has the Install button beside these chips, which says so.
        if game.isEXoGame, installed, !model.isDocumentItem(game) {
            chips.append(Chip(text: "Installed", tone: .good, systemImage: "checkmark.circle.fill"))
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
                        text: problemLabel(resolved), tone: .warning, systemImage: "exclamationmark.triangle.fill",
                        help: resolved.problem))
            if resolved.isReady, let problem = model.missingFirmware(for: game, resolved: resolved) {
                chips.append(
                    Chip(
                        text: "BIOS missing", tone: .warning, systemImage: "exclamationmark.triangle.fill",
                        help: problem))
            }
        case .scummVM:
            if let installation = model.scummVMInstallation(for: game, variant: nil), installation.exists {
                chips.append(Chip(text: installation.kind.displayName, tone: .good, systemImage: "cpu"))
            } else {
                chips.append(
                    Chip(
                        text: "ScummVM missing", tone: .warning, systemImage: "exclamationmark.triangle.fill",
                        help: Self.missingHelp(.scummVM)))
            }
        case .interactiveFiction:
            if installed {
                let variants = model.launchVariants(for: game)
                if let variant = model.preferredVariant(for: game, in: variants), let reason = variant.unsupportedReason
                {
                    chips.append(
                        Chip(
                            text: "Cannot start yet", tone: .warning, systemImage: "exclamationmark.triangle.fill",
                            help: "\(variant.title): \(reason)."))
                } else {
                    chips.append(emulatorChip(model.emulatorKind(for: game)))
                }
            }
        case .appleIIGS:
            if let reason = model.appleIIGSProblem(for: game) {
                chips.append(
                    Chip(
                        text: "ROM missing", tone: .warning, systemImage: "exclamationmark.triangle.fill",
                        help: reason + "."))
            } else {
                chips.append(emulatorChip(model.appleIIGSRoute(for: game).emulator))
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
            text: "\(kind.displayName) missing", tone: .warning, systemImage: "exclamationmark.triangle.fill",
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
