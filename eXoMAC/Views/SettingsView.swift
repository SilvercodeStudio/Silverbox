import SwiftUI
import UniformTypeIdentifiers
import eXoCore

/// Lets other windows open Settings on a given tab.
@Observable
final class SettingsState {
    static let shared = SettingsState()

    struct Request: Equatable {
        let id = UUID()
        let tab: SettingsView.Tab
    }

    private(set) var request: Request?

    func show(tab: SettingsView.Tab) {
        request = Request(tab: tab)
    }
}

struct SettingsView: View {
    enum Tab: String { case general, library, emulators, display }
    /// Debug builds can start on a tab with `-settingsTab emulators`.
    @State private var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "settingsTab") ?? "") ?? .general

    var body: some View {
        let state = SettingsState.shared
        TabView(selection: $tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
                .tag(Tab.general)
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "folder") }
                .tag(Tab.library)
            EmulatorSettingsView()
                .tabItem { Label("Emulators", systemImage: "display") }
                .tag(Tab.emulators)
            DisplaySettingsView()
                .tabItem { Label("Display & Sound", systemImage: "tv.and.hifispeaker.fill") }
                .tag(Tab.display)
        }
        .frame(width: 640)
        .onAppear { if let request = state.request { tab = request.tab } }
        .onChange(of: state.request) { _, request in if let request { tab = request.tab } }
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("App icon") {
                HStack(spacing: 20) {
                    ForEach(AppIconVariant.allCases) { variant in
                        AppIconChoice(variant: variant, isSelected: model.settings.appIcon == variant) {
                            model.settings.appIcon = variant
                        }
                    }
                }
                Text(
                    "The Dock and the About window show the chosen icon. The Finder shows the amber icon built into the app."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu music") {
                Toggle("Play a game's music while browsing", isOn: $model.settings.musicEnabled)
                Slider(value: $model.settings.musicVolume, in: 0...1) { Text("Volume") }
                Toggle("Keep playing when another app is in front", isOn: $model.settings.musicInBackground)
                Text(
                    "MP3, Ogg Vorbis and MOD, S3M, XM and IT tracker modules play. AMF modules and VOC files are listed but skipped."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            VideoPlayerSettingsSection()
            Section("Playing") {
                Toggle("Show launch options before each game", isOn: $model.settings.showLaunchOptions)
                Text(
                    "The dialog offers the game's versions, full screen or window, shader or filter, and emulator, like the menus eXoDOS shows in its console window. Configure in a game's menu opens the same dialog to save choices for that game."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Library view") {
                Toggle("Show hidden games", isOn: $model.settings.showHiddenGames)
            }
            Section("Game controller") {
                if model.gamepad.controllerNames.isEmpty {
                    Text("No controller connected")
                } else {
                    // Two controllers of one model have the same name.
                    ForEach(Array(model.gamepad.controllerNames.enumerated()), id: \.offset) { Text($0.element) }
                }
                Text(
                    "Browse with the D-pad or left stick; the main button plays, the back button closes; the shoulder buttons step through a game's images and the other face buttons Quick Look an image or open the game page. See Help for the full map."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

struct LibrarySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingPicker = false
    @State private var showingLocalPicker = false

    /// A whole drive or the home folder gets an "Autoexec.Mac" folder of its
    /// own, so the app's folders do not land at the root.
    static func dataFolder(for chosen: URL) -> URL {
        let url = chosen.standardizedFileURL
        let isVolumeRoot = url.pathComponents.count == 3 && url.pathComponents[1] == "Volumes"
        let isHome = url == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        return isVolumeRoot || isHome || url.path == "/"
            ? url.appendingPathComponent("Autoexec.Mac", isDirectory: true) : url
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Collections") {
                ForEach($model.settings.collections) { $collection in
                    CollectionEditor(collection: $collection)
                }
                HStack {
                    Button("Add Collection…") { showingPicker = true }
                    Spacer()
                    if let library = model.library {
                        Text(
                            "\(library.games.count.formatted()) games in \(library.snapshots.count) collection\(library.snapshots.count == 1 ? "" : "s")"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button("Rescan All") { model.reloadLibrary(clearMediaCache: true) }
                        .disabled(model.collections.isEmpty)
                }
                Text(
                    "A collection is an eXoDOS install or any LaunchBox library folder; you can also drop one here from the Finder. Rescan after you add or update packs."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local data folder") {
                HStack {
                    Text(model.localStore.directory.path)
                        .font(Theme.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { showingLocalPicker = true }
                    if model.settings.localStorePath != nil {
                        Button("Use Default") { model.settings.localStorePath = nil }
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.localStore.directory])
                    }
                }
                if model.settings.localStorePath != nil,
                    !FileManager.default.fileExists(atPath: model.localStore.directory.path)
                {
                    Label(
                        "This folder is not available right now. Is the drive connected? Installs, soundtracks and caches wait until it is.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
                Text(
                    "Installed games, save backups, edited configs, unpacked soundtracks, caches, launch configs and logs are kept here, so the collections can stay read-only; an external drive works. Favorites, play history and settings stay on this Mac. Choosing another folder does not move what is already there."
                )
                .font(.caption).foregroundStyle(.secondary)
                Picker("Install games to", selection: $model.settings.installLocation) {
                    ForEach(InstallLocation.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .dropDestination(for: URL.self) { urls, _ in
            model.addDroppedFolders(urls)
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addFolder(url) }
        }
        .fileImporter(isPresented: $showingLocalPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let folder = Self.dataFolder(for: url)
                try? LocalStore(directory: folder).ensureDirectories()
                model.settings.localStorePath = folder.path
            }
        }
    }
}

/// One collection: name, folder, enabled, path substitutions and what was found.
struct CollectionEditor: View {
    @Binding var collection: LibraryCollection
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var pickingRoot = false
    @State private var pickingSubstitution: UUID?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Name", text: $collection.name)
                        .frame(maxWidth: 240)
                    Toggle("Enabled", isOn: $collection.isEnabled)
                    Spacer()
                    Button("Remove", role: .destructive) { model.removeCollection(id: collection.id) }
                }
                HStack {
                    Text(collection.rootPath).font(Theme.mono).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { pickingRoot = true }
                }
                if let error = model.loadErrors[collection.id] {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
                }
                if let report = model.rootReports[collection.id] {
                    LibraryRootReportView(report: report)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Path substitutions").font(.subheadline.weight(.semibold))
                    Text(
                        "Map a Windows prefix used in the library, such as X:\\Emulation or the Games folder, to a folder on this Mac."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    ForEach($collection.substitutions) { $substitution in
                        HStack {
                            TextField("Windows prefix", text: $substitution.windowsPrefix)
                                .font(Theme.mono)
                                .frame(width: 180)
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(substitution.macPath.isEmpty ? "Choose a folder" : substitution.macPath)
                                .font(Theme.mono).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(substitution.macPath.isEmpty ? .secondary : .primary)
                            Spacer()
                            Button("Choose…") { pickingSubstitution = substitution.id }
                            Button {
                                collection.substitutions.removeAll { $0.id == substitution.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Substitution") {
                        collection.substitutions.append(PathSubstitution(windowsPrefix: "Games", macPath: ""))
                    }
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                Text(collection.name).fontWeight(.semibold)
                if !collection.isEnabled { Text("(disabled)").foregroundStyle(.secondary) }
                Spacer()
                if let snapshot = model.library?.snapshot(id: collection.id) {
                    Text("\(snapshot.games.count.formatted()) games").foregroundStyle(.secondary)
                }
            }
        }
        .fileImporter(isPresented: $pickingRoot, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { collection.rootPath = url.path }
        }
        .fileImporter(
            isPresented: Binding(get: { pickingSubstitution != nil }, set: { if !$0 { pickingSubstitution = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result, let id = pickingSubstitution,
                let index = collection.substitutions.firstIndex(where: { $0.id == id })
            {
                collection.substitutions[index].macPath = url.path
            }
            pickingSubstitution = nil
        }
    }
}

struct EmulatorSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var picking: EmulatorKind?
    @State private var pickingCores = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("DOSBox for eXoDOS games") {
                Picker("Default", selection: $model.settings.emulatorPolicy) {
                    ForEach(EmulatorPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                Text(
                    "eXoDOS picks a DOSBox build per game (0.74, ECE, Staging, SVN Daum or DOSBox-X). “Match” maps Daum and DOSBox-X games to DOSBox-X and everything else to DOSBox Staging. You can override any game in its info sheet."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(EmulatorKind.dosBox) { kind in
                Section(kind.displayName) {
                    EmulatorPathRow(kind: kind, picking: $picking)
                    if kind == .dosboxStaging, let installation = model.settings.emulatorInstallation(kind) {
                        Text(
                            EmulatorCapabilities.fluidSynthAvailable(for: installation)
                                ? "FluidSynth is available for General MIDI with the eXoDOS Sound Canvas SoundFont."
                                : "FluidSynth is not installed, so General MIDI games use the macOS synthesizer. Install it with Homebrew (brew install fluid-synth) for the eXoDOS SoundFont."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("eXoWin9x games") {
                Text(
                    "eXoWin9x games start Windows 98 in DOSBox-X. About thirty need a full PC with a 3dfx Voodoo card; eXo runs those in 86Box."
                )
                .font(.caption).foregroundStyle(.secondary)
                EmulatorPathRow(kind: .box86, picking: $picking)
            }
            Section("Consoles, computers and arcade") {
                Text(
                    "Games from a LaunchBox library start in the emulator assigned to their platform. RetroArch covers most platforms through its cores, Dolphin runs GameCube and Wii, MAME runs arcade sets and Mednafen covers a few more consoles. A platform without a choice of its own follows the library's Emulators.xml, mapped to the Mac emulators found here."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(EmulatorKind.romEmulators) { kind in
                Section(kind.displayName) {
                    EmulatorPathRow(kind: kind, picking: $picking)
                    Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                    if kind == .retroArch { retroArchCoresRow }
                }
            }
            Section("Platforms") {
                PlatformAssignmentsView()
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: [.applicationBundle, .unixExecutable]
        ) { result in
            if case .success(let url) = result, let kind = picking {
                model.settings.setEmulatorPath(url.path, for: kind)
            }
            picking = nil
        }
        .fileImporter(isPresented: $pickingCores, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.settings.retroArchCoresPath = url.path }
        }
    }

    @ViewBuilder
    private var retroArchCoresRow: some View {
        let setup = model.settings.retroArchSetup
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cores folder").font(.subheadline)
                Text(setup?.coresDirectory?.path ?? (setup == nil ? "RetroArch is not installed" : "Not found"))
                    .font(Theme.mono).lineLimit(1).truncationMode(.middle)
                if let setup, setup.coresDirectory != nil {
                    let count = setup.installedCores().count
                    Text(
                        count == 0
                            ? "No cores installed yet. Download them in RetroArch under Online Updater › Core Downloader."
                            : "\(count) cores installed"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Choose…") { pickingCores = true }
            if model.settings.retroArchCoresPath != nil {
                Button("Auto-detect") { model.settings.retroArchCoresPath = nil }
            }
        }
    }
}

/// Where one emulator is installed, with Choose and Auto-detect.
struct EmulatorPathRow: View {
    let kind: EmulatorKind
    @Binding var picking: EmulatorKind?
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let installation = model.settings.emulatorInstallation(kind)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(installation?.executableURL.path ?? "Not found")
                    .font(Theme.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let installation {
                    Label(
                        installation.exists ? "Ready" : "Executable missing",
                        systemImage: installation.exists ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(installation.exists ? Theme.accent : .red)
                } else if let url = URL(string: kind.website) {
                    Link("Download from \(url.host ?? kind.website)", destination: url).font(.caption)
                }
            }
            Spacer()
            Button("Choose…") { picking = kind }
            if model.settings.emulatorPath(for: kind) != nil {
                Button("Auto-detect") { model.settings.setEmulatorPath(nil, for: kind) }
            }
        }
    }
}

/// One row per platform with ROM games: which emulator and core run it.
struct PlatformAssignmentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let resolver = model.emulatorResolver()
        let cores = model.settings.retroArchSetup?.installedCores() ?? []
        if model.romPlatforms.isEmpty {
            Text("No console, computer or arcade platforms are loaded. Add a LaunchBox library in the Library tab.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            ForEach(model.romPlatforms) { platform in
                PlatformAssignmentRow(
                    platform: platform, resolved: resolver.resolve(platform: platform.name), cores: cores)
            }
        }
    }
}

struct PlatformAssignmentRow: View {
    let platform: AppModel.RomPlatformSummary
    let resolved: ResolvedEmulatorAssignment
    let cores: [RetroArchCore]
    @Environment(AppModel.self) private var model

    private var userAssignment: PlatformEmulatorAssignment? { model.settings.platformAssignment(for: platform.name) }
    private var effectiveKind: EmulatorKind? { userAssignment?.emulator ?? resolved.assignment?.emulator }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name).fontWeight(.semibold)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Emulator", selection: emulatorBinding) {
                    Text("Automatic").tag(EmulatorKind?.none)
                    ForEach(EmulatorKind.romEmulators) { Text($0.displayName).tag(EmulatorKind?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 112)
                if effectiveKind == .retroArch {
                    Picker("Core", selection: coreBinding) {
                        Text("Choose a core").tag(String?.none)
                        ForEach(missingCores, id: \.self) { Text("\($0) (missing)").tag(String?.some($0)) }
                        ForEach(cores) { Text($0.title).tag(String?.some($0.name)) }
                    }
                    .labelsHidden()
                    .frame(width: 236)
                }
            }
            if userAssignment != nil {
                TextField("Extra arguments", text: argumentsBinding)
                    .font(Theme.mono)
                    .textFieldStyle(.roundedBorder)
            }
            Label(status, systemImage: resolved.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(resolved.isReady ? Theme.accent : .orange)
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var text = platform.gameCount == 1 ? "1 game" : "\(platform.gameCount) games"
        if let title = resolved.launchBoxEmulatorTitle {
            text += " · LaunchBox uses \(title)"
            if let core = resolved.launchBoxCore { text += " with \(core)" }
        }
        return text
    }

    private var status: String {
        if resolved.isReady {
            let origin = resolved.source == .user ? "" : " (from LaunchBox)"
            return "Ready: \(resolved.summary)\(origin)"
        }
        // The hint to open Settings is redundant here.
        return (resolved.problem ?? "Not ready")
            .replacingOccurrences(of: " Choose it in Settings › Emulators.", with: "")
            .replacingOccurrences(of: " Choose an emulator in Settings › Emulators.", with: "")
            .replacingOccurrences(of: " Choose one in Settings › Emulators.", with: "")
            .replacingOccurrences(of: " in Settings › Emulators.", with: ".")
    }

    /// Cores named by LaunchBox or the user that are not in the cores folder.
    private var missingCores: [String] {
        let installed = Set(cores.map(\.name))
        var names: [String] = []
        for candidate in [resolved.launchBoxCore, userAssignment?.core, resolved.assignment?.core].compactMap({ $0 }) {
            let name = RetroArchSetup.coreName(from: candidate)
            if !installed.contains(name), !names.contains(name) { names.append(name) }
        }
        return names
    }

    private var emulatorBinding: Binding<EmulatorKind?> {
        Binding(
            get: { userAssignment?.emulator },
            set: { kind in
                guard let kind else {
                    model.settings.setPlatformAssignment(nil, for: platform.name)
                    return
                }
                let previous = userAssignment
                let core = kind == .retroArch ? (previous?.core ?? resolved.launchBoxCore) : nil
                let arguments =
                    previous?.arguments
                    ?? (resolved.assignment?.emulator == kind ? resolved.assignment?.arguments ?? "" : "")
                model.settings.setPlatformAssignment(
                    PlatformEmulatorAssignment(
                        platform: platform.name, emulator: kind, core: core, arguments: arguments),
                    for: platform.name)
            }
        )
    }

    private var coreBinding: Binding<String?> {
        Binding(
            get: {
                let core =
                    userAssignment?.core
                    ?? (resolved.assignment?.emulator == .retroArch ? resolved.assignment?.core : nil)
                return core.map { RetroArchSetup.coreName(from: $0) }
            },
            set: { core in
                model.settings.setPlatformAssignment(
                    PlatformEmulatorAssignment(
                        platform: platform.name, emulator: .retroArch, core: core,
                        arguments: userAssignment?.arguments ?? ""),
                    for: platform.name)
            }
        )
    }

    private var argumentsBinding: Binding<String> {
        Binding(
            get: { userAssignment?.arguments ?? "" },
            set: { text in
                guard var assignment = userAssignment else { return }
                assignment.arguments = text
                model.settings.setPlatformAssignment(assignment, for: platform.name)
            }
        )
    }
}

struct DisplaySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Window") {
                Toggle("Start games in full screen", isOn: $model.settings.launchOptions.fullscreen)
                Picker("Window size", selection: $model.settings.launchOptions.windowSize) {
                    ForEach(LaunchOptions.WindowSize.allCases) { Text($0.displayName).tag($0) }
                }
                Text(
                    "Automatic lets DOSBox Staging size the window for your screen. DOSBox-X then uses the size in the game's config, which eXoDOS sets for a 1080p desktop."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Picture") {
                Picker("Aspect ratio correction", selection: $model.settings.launchOptions.aspect) {
                    ForEach(LaunchOptions.AspectMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Shader (DOSBox Staging)", selection: $model.settings.launchOptions.shader) {
                    ForEach(LaunchOptions.Shader.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Graphics filter (DOSBox-X)", selection: $model.settings.launchOptions.scaler) {
                    ForEach(LaunchOptions.Scaler.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Skip the emulator's start-up banner", isOn: $model.settings.launchOptions.quietStartup)
            }
            Section("General MIDI music") {
                Picker("Render General MIDI with", selection: $model.settings.launchOptions.generalMIDI) {
                    ForEach(LaunchOptions.GeneralMIDI.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Games set up for the Roland MT-32 always use the MT-32 emulation with the ROMs in eXo/mt32.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

/// One app icon in the General tab, highlighted when it is the chosen one.
struct AppIconChoice: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: variant.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 80, height: 80)
                Text(variant.displayName)
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
