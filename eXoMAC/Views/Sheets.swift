import SwiftUI

/// Confirms installation (unzipping) of a game.
struct InstallSheet: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var playAfter = true
    @State private var installing = false

    var body: some View {
        let plan = model.library.flatMap { GameInstaller(snapshot: $0).plan(for: game) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BoxArtView(game: game, width: 56, maxPixelSize: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install \(game.title)?").font(.headline)
                    Text("This game must be installed before it can run for the first time. The archive is unpacked into eXo/eXoDOS, exactly as eXoDOS does on Windows.")
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let plan {
                VStack(alignment: .leading, spacing: 4) {
                    Text(WindowsPath.posix(plan.archiveURL.path.replacingOccurrences(of: model.libraryRoot?.url.path ?? "", with: "")))
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                    if plan.archiveExists, let size = plan.archiveSize {
                        Text("Archive size: \(Formatters.bytes(size))").font(.caption).foregroundStyle(Theme.textTertiary)
                    } else if !plan.archiveExists {
                        Label("The archive is not present. This may be the Lite edition; downloading games is not supported yet.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    if plan.updateArchiveURL != nil {
                        Text("An eXoDOS update for this game will be applied after unpacking.").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            Toggle("Play when installation finishes", isOn: $playAfter)
            HStack {
                if installing {
                    ProgressView().controlSize(.small)
                    Text("Unpacking…").foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(installing)
                Button("Install") {
                    installing = true
                    Task {
                        await model.install(game, playAfter: playAfter)
                        installing = false
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(installing || plan?.archiveExists != true)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Per-game settings: emulator, version, status flags, and the file paths.
struct GameInfoSheet: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        let variants = model.launchVariants(for: game)
        let build = model.eXoDOSBuild(for: game)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BoxArtView(game: game, width: 36, maxPixelSize: 120)
                VStack(alignment: .leading) {
                    Text(game.title).font(.headline)
                    Text("Game info").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()
            Form {
                if game.isDOSGame {
                    Section("Launch") {
                        LabeledContent("Launcher") { PathText(game.applicationPath) }
                        LabeledContent("Installer") { PathText(game.configurationPath ?? "") }
                        if let root = game.rootFolder {
                            LabeledContent("DOSBox config") { PathText(root + "\\dosbox.conf") }
                        }
                        LabeledContent("eXoDOS build") { Text(build?.displayName ?? "Unknown") }
                        Picker("Emulator", selection: emulatorBinding) {
                            Text("Automatic (\(model.settings.emulatorPolicy == .recommended ? (build?.recommendedEmulator ?? .dosboxStaging).displayName : "per Settings"))").tag(EmulatorKind?.none)
                            ForEach(EmulatorKind.allCases) { kind in
                                Text(kind.displayName).tag(EmulatorKind?.some(kind))
                            }
                        }
                        if variants.count > 1 {
                            Picker("Version to play", selection: variantBinding) {
                                Text("First available").tag(String?.none)
                                ForEach(variants) { variant in
                                    Text(variant.title + (variant.needsWindowsHelper ? " (needs a Windows helper)" : "")).tag(String?.some(variant.id))
                                }
                            }
                        }
                    }
                }
                Section("Media") {
                    LabeledContent("Manual") { PathText(game.manualPath ?? "") }
                    LabeledContent("Music") { PathText(game.musicPath ?? "") }
                }
                Section("Status") {
                    Toggle("Favorite", isOn: flag(\.favorite, fallback: game.favorite))
                    Toggle("Completed", isOn: flag(\.completed, fallback: game.completed))
                    Toggle("Hidden from library", isOn: flag(\.hidden, fallback: game.hidden))
                    Toggle("Broken", isOn: flag(\.broken, fallback: game.broken))
                    if game.isDOSGame, model.isInstalled(game) {
                        Button("Uninstall…", role: .destructive) {
                            model.uninstall(game)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Changes are kept by eXoMAC; the LaunchBox files are not modified.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 560)
    }

    private var emulatorBinding: Binding<EmulatorKind?> {
        Binding(
            get: { model.userState.state(for: game.id).emulatorOverride },
            set: { value in model.userState.update(game.id) { $0.emulatorOverride = value } }
        )
    }

    private var variantBinding: Binding<String?> {
        Binding(
            get: { model.userState.state(for: game.id).preferredVariantID },
            set: { value in model.userState.update(game.id) { $0.preferredVariantID = value } }
        )
    }

    private func flag(_ keyPath: WritableKeyPath<GameUserState, Bool?>, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { model.userState.state(for: game.id)[keyPath: keyPath] ?? fallback },
            set: { value in
                model.userState.update(game.id) { $0[keyPath: keyPath] = value == fallback ? nil : value }
                model.refreshVisibleGames()
            }
        )
    }
}

struct PathText: View {
    let path: String
    init(_ path: String) { self.path = path }

    var body: some View {
        Text(path.isEmpty ? "—" : WindowsPath.posix(path))
            .font(Theme.mono)
            .foregroundStyle(Theme.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
