import SwiftUI
import eXoCore

/// Confirms installation (unzipping) of a game.
struct InstallSheet: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var playAfter = true
    @State private var restoreSaves = true
    @State private var installing = false

    var body: some View {
        let plan = model.installer(for: game)?.plan(for: game)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BoxArtView(game: game, width: 56, maxPixelSize: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install \(game.title)?").font(.headline)
                    Text(
                        plan?.location == .inPlace
                            ? "This game must be installed before it can run for the first time. The archive is unpacked into eXo/eXoDOS, exactly as eXoDOS does on Windows."
                            : "This game must be installed before it can run for the first time. The archive is unpacked into the local data folder; the eXoDOS folder is not changed."
                    )
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let plan {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        plan.archiveURL.path.replacingOccurrences(
                            of: (model.snapshot(for: game)?.root.url.path ?? "") + "/", with: "")
                    )
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    if plan.archiveExists, let size = plan.archiveSize {
                        Text("Archive size: \(Formatters.bytes(size))").font(.caption).foregroundStyle(
                            Theme.textTertiary)
                    } else if !plan.archiveExists {
                        Label(
                            "The archive is not present. This may be the Lite edition; downloading games is not supported yet.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .font(.caption)
                    }
                    if plan.updateArchiveURL != nil {
                        Text("An eXoDOS update for this game will be applied after unpacking.").font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            if let plan, plan.saveArchiveURL != nil {
                Toggle(
                    "Restore saved progress from the backup made \(Formatters.date(plan.saveArchiveDate))",
                    isOn: $restoreSaves)
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
                        await model.install(
                            game, playAfter: playAfter, restoreSaves: restoreSaves && plan?.saveArchiveURL != nil)
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
    @Environment(\.openSettings) private var openSettings

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
                        if let location = model.library?.installedLocation(for: game) {
                            LabeledContent(location.isLocal ? "Installed in local data" : "Installed in library") {
                                Text(location.url.path).font(Theme.mono).foregroundStyle(Theme.textSecondary).lineLimit(
                                    1
                                ).truncationMode(.middle)
                            }
                        }
                        LabeledContent("Edited config") {
                            HStack {
                                if model.overrideConfigURL(for: game) != nil {
                                    Text("In use").foregroundStyle(Theme.accent)
                                    Button("Open") { model.editConfig(for: game) }
                                    Button("Revert") { model.revertConfig(for: game) }
                                } else {
                                    Button("Edit a Copy…") { model.editConfig(for: game) }
                                }
                            }
                        }
                        if !(model.userState.state(for: game.launchBoxID).launchOverrides?.isEmpty ?? true) {
                            LabeledContent("Remembered launch options") {
                                Button("Forget") { model.forgetLaunchChoices(for: game) }
                            }
                        }
                        Picker("Emulator", selection: emulatorBinding) {
                            Text(
                                "Automatic (\(model.settings.emulatorPolicy == .recommended ? (build?.recommendedEmulator ?? .dosboxStaging).displayName : "per Settings"))"
                            ).tag(EmulatorKind?.none)
                            ForEach(EmulatorKind.dosBox) { kind in
                                Text(kind.displayName).tag(EmulatorKind?.some(kind))
                            }
                        }
                        if variants.count > 1 {
                            Picker("Version to play", selection: variantBinding) {
                                Text("First available").tag(String?.none)
                                ForEach(variants) { variant in
                                    Text(
                                        variant.title + (variant.needsWindowsHelper ? " (needs a Windows helper)" : "")
                                    ).tag(String?.some(variant.id))
                                }
                            }
                        }
                    }
                }
                if game.launchKind == .windows9x {
                    Section("Launch") {
                        LabeledContent("Launcher") { PathText(game.applicationPath) }
                        if let root = game.rootFolder {
                            let kind = model.emulatorKind(for: game)
                            LabeledContent("\(kind.displayName) config") {
                                PathText(root + (kind == .box86 ? "\\Play.cfg" : "\\Play.conf"))
                            }
                        }
                        LabeledContent("Emulator") {
                            Text("Windows 98 in \(model.emulatorKind(for: game).displayName)")
                        }
                        if let location = model.library?.installedLocation(for: game) {
                            LabeledContent(location.isLocal ? "Installed in local data" : "Installed in library") {
                                Text(location.url.path).font(Theme.mono).foregroundStyle(Theme.textSecondary).lineLimit(
                                    1
                                ).truncationMode(.middle)
                            }
                        }
                        if !(model.userState.state(for: game.launchBoxID).launchOverrides?.isEmpty ?? true) {
                            LabeledContent("Remembered launch options") {
                                Button("Forget") { model.forgetLaunchChoices(for: game) }
                            }
                        }
                    }
                }
                if game.launchKind == .emulator {
                    let resolved = model.resolvedEmulator(for: game)
                    Section("Launch") {
                        LabeledContent("File") { PathText(game.applicationPath) }
                        if let title = resolved.launchBoxEmulatorTitle {
                            LabeledContent("LaunchBox runs with") {
                                Text(title + (resolved.launchBoxCore.map { " · \($0)" } ?? ""))
                            }
                        }
                        LabeledContent("Mac emulator") {
                            HStack {
                                Text(resolved.isReady ? resolved.summary : (resolved.problem ?? "Not ready"))
                                    .foregroundStyle(resolved.isReady ? Theme.accent : .orange)
                                    .multilineTextAlignment(.trailing)
                                Button("Emulator Settings…") {
                                    SettingsState.shared.show(tab: .emulators)
                                    openSettings()
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
                    if game.isEXoGame, model.isInstalled(game) {
                        Button("Uninstall…", role: .destructive) {
                            dismiss()
                            model.pendingUninstall = game
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Changes are kept in the local data folder; the eXoDOS files are not modified.")
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
            get: { model.userState.state(for: game.launchBoxID).emulatorOverride },
            set: { value in model.userState.update(game.launchBoxID) { $0.emulatorOverride = value } }
        )
    }

    private var variantBinding: Binding<String?> {
        Binding(
            get: { model.userState.state(for: game.launchBoxID).preferredVariantID },
            set: { value in model.userState.update(game.launchBoxID) { $0.preferredVariantID = value } }
        )
    }

    private func flag(_ keyPath: WritableKeyPath<GameUserState, Bool?>, fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { model.userState.state(for: game.launchBoxID)[keyPath: keyPath] ?? fallback },
            set: { value in
                model.userState.update(game.launchBoxID) { $0[keyPath: keyPath] = value == fallback ? nil : value }
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

/// Confirms removal of an installed game, with an optional save backup.
struct UninstallSheet: View {
    let game: Game
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var backup = true
    @State private var working = false

    var body: some View {
        let plan = model.installer(for: game)?.plan(for: game)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BoxArtView(game: game, width: 56, maxPixelSize: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Uninstall \(game.title)?").font(.headline)
                    Text(
                        "The game folder is removed. The archive stays in the collection, so you can install the game again at any time."
                    )
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let plan {
                Text(plan.installedFolderURL.path).font(Theme.mono).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    .truncationMode(.middle)
                Toggle("Back up saved games and changed files first", isOn: $backup)
                    .disabled(!plan.archiveExists)
                Text(
                    backup && plan.archiveExists
                        ? "Only files that are new or changed since installation are saved, to \(plan.saveBackupURL.path)."
                        : "Saved games in the folder will be lost."
                )
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("Backing up…").foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button("Uninstall", role: .destructive) {
                    working = true
                    Task {
                        await model.uninstall(game, backupSaves: backup && plan?.archiveExists == true)
                        working = false
                        dismiss()
                    }
                }
                .disabled(working || plan == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// The native stand-in for eXoDOS's console menus: version, display and
/// emulator choices before a game starts.
struct LaunchOptionsSheet: View {
    let pending: AppModel.PendingLaunch
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var options: LaunchOptions
    @State private var variantID: String?
    @State private var emulator: EmulatorKind
    @State private var remember: Bool
    @State private var choices = LaunchChoices()

    init(pending: AppModel.PendingLaunch) {
        self.pending = pending
        _options = State(initialValue: LaunchOptions())
        _variantID = State(initialValue: nil)
        _emulator = State(initialValue: .dosboxStaging)
        _remember = State(initialValue: false)
    }

    private var isScummVM: Bool { pending.game.launchKind == .scummVM }
    private var selectedVariant: LaunchVariant? { pending.variants.first { $0.id == variantID } }

    var body: some View {
        @Bindable var model = model
        let game = pending.game
        let build = model.eXoDOSBuild(for: game)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BoxArtView(game: game, width: 56, maxPixelSize: 160)
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title).font(.headline)
                    Text(subtitle(build: build))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    HelpState.shared.show(topicPrefix: "03")
                    openWindow(id: "help")
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Explain these options")
            }
            .padding(16)
            Divider()
            Form {
                if pending.variants.count > 1 {
                    Section("Version") {
                        Picker("Play", selection: $variantID) {
                            ForEach(pending.variants) { variant in
                                Text(variant.title + (variant.needsWindowsHelper ? " (needs a Windows helper)" : ""))
                                    .tag(String?.some(variant.id))
                            }
                        }
                        .pickerStyle(.radioGroup)
                        if isScummVM, let note = model.scummVMNote(for: game, variant: selectedVariant) {
                            Text(note).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                } else if isScummVM, let note = model.scummVMNote(for: game, variant: selectedVariant) {
                    Section("Note") {
                        Text(note).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                if isScummVM, let variant = selectedVariant { scummVMChoices(variant) }
                Section("Display") {
                    Toggle("Full screen", isOn: $options.fullscreen)
                    if emulator != .box86 { displayOptions }
                }
                Section("Emulator") {
                    if game.launchKind == .windows9x {
                        LabeledContent("Emulator") { Text("Windows 98 in \(emulator.displayName)") }
                    } else if isScummVM {
                        LabeledContent("Emulator") {
                            Text(
                                model.scummVMInstallation(for: game, variant: selectedVariant)?.kind.displayName
                                    ?? "ScummVM")
                        }
                    } else {
                        Picker("Emulator", selection: $emulator) {
                            ForEach(EmulatorKind.dosBox) { kind in
                                Text(
                                    kind.displayName
                                        + (kind == model.defaultEmulatorKind(for: game) ? " (default)" : "")
                                )
                                .tag(kind)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                Section {
                    if !pending.configureOnly {
                        Toggle("Remember these choices for this game", isOn: $remember)
                    }
                    Toggle("Show this dialog before each game", isOn: $model.settings.showLaunchOptions)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Game Info…") {
                    dismiss()
                    model.pendingInfoGame = game
                }
                if pending.configureOnly, remember {
                    Button("Use Defaults") {
                        dismiss()
                        model.forgetLaunchChoices(for: game)
                    }
                    .help("Forget the choices saved for this game")
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(pending.configureOnly ? "Save" : "Play") {
                    let variant = pending.variants.first { $0.id == variantID }
                    if remember || pending.configureOnly {
                        model.rememberLaunchChoices(
                            for: game, options: options, variant: variant, emulatorKind: emulator, choices: choices)
                    }
                    dismiss()
                    if !pending.configureOnly {
                        model.launch(game, variant: variant, options: options, emulatorKind: emulator, choices: choices)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !pending.configureOnly && pending.variants.first { $0.id == variantID }?.needsWindowsHelper == true)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear {
            options = model.effectiveLaunchOptions(for: game)
            emulator = model.emulatorKind(for: game)
            variantID = model.preferredVariant(for: game, in: pending.variants)?.id
            let state = model.userState.state(for: game.launchBoxID)
            choices = state.launchChoices ?? LaunchChoices()
            remember =
                !(state.launchOverrides?.isEmpty ?? true) || state.preferredVariantID != nil
                || state.emulatorOverride != nil || state.launchChoices != nil
        }
    }

    /// The music device and subtitles, when eXo asks for them.
    @ViewBuilder private func scummVMChoices(_ variant: LaunchVariant) -> some View {
        let files = model.scummVMFiles(for: variant)
        let hasSubtitles = !variant.id.contains("/") && files.subtitle != nil
        if !files.musicChoices.isEmpty || hasSubtitles {
            Section("Sound") {
                if !files.musicChoices.isEmpty {
                    Picker("Music", selection: musicBinding(files.musicChoices)) {
                        ForEach(files.musicChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }
                if hasSubtitles {
                    Toggle(
                        "Subtitles",
                        isOn: Binding(get: { choices.subtitles ?? true }, set: { choices.subtitles = $0 }))
                }
            }
        }
    }

    /// The remembered music device when this variant offers it, else its first.
    private func musicBinding(_ available: [String]) -> Binding<String> {
        Binding(
            get: { choices.music.flatMap { available.contains($0) ? $0 : nil } ?? available[0] },
            set: { choices.music = $0 })
    }

    /// Window, aspect and filter choices; 86Box has only full screen.
    @ViewBuilder private var displayOptions: some View {
        Picker("Window size", selection: $options.windowSize) {
            ForEach(LaunchOptions.WindowSize.allCases) { Text($0.displayName).tag($0) }
        }
        .disabled(options.fullscreen)
        Picker("Aspect ratio correction", selection: $options.aspect) {
            ForEach(LaunchOptions.AspectMode.allCases) { Text($0.displayName).tag($0) }
        }
        if isScummVM {
            EmptyView()
        } else if emulator == .dosboxStaging {
            Picker("CRT shader", selection: $options.shader) {
                ForEach(LaunchOptions.Shader.allCases) { Text($0.displayName).tag($0) }
            }
        } else {
            Picker("Graphics filter", selection: $options.scaler) {
                ForEach(LaunchOptions.Scaler.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private func subtitle(build: EXoDOSBuild?) -> String {
        let pack = pending.game.eXoPack?.displayName ?? "eXo"
        let runs: String?
        if pending.game.launchKind == .windows9x {
            runs = "Windows 98 starts first, then the game."
        } else if isScummVM {
            runs = model.scummVMVersion(for: pending.game, variants: pending.variants, variant: selectedVariant).map {
                "\(pack) runs this game in ScummVM \($0)."
            }
        } else {
            runs = build.map { "\(pack) runs this game with \($0.displayName)." }
        }
        if pending.configureOnly {
            return "These choices are saved for this game and used each time it starts." + (runs.map { " " + $0 } ?? "")
        }
        return runs ?? "Launch options"
    }
}
