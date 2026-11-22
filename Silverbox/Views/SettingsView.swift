import SwiftUI
import UniformTypeIdentifiers
import SilverboxCore

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
        // A fixed size, as macOS settings windows are; long tabs scroll.
        .frame(width: 780, height: 640)
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
                Text("The Dock and the About window show the chosen icon. The Finder always shows the amber one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Menu music") {
                Toggle("Play a game's music while browsing", isOn: $model.settings.musicEnabled)
                Group {
                    Slider(value: $model.settings.musicVolume, in: 0...1) { Text("Volume") }
                    Toggle("Keep playing when another app is in front", isOn: $model.settings.musicInBackground)
                }
                .disabled(!model.settings.musicEnabled)
                .help(model.settings.musicEnabled ? "" : "Turn the music on first")
                Text("MP3, Ogg Vorbis and tracker modules play; Help lists the formats.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VideoPlayerSettingsSection()
            Section("Playing") {
                Toggle("Show launch options before each game", isOn: $model.settings.showLaunchOptions)
                Text("The dialog offers the game's versions, full screen or a window, the shader and the emulator.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Library view") {
                Toggle("Show hidden games", isOn: $model.settings.showHiddenGames)
                Toggle("Show keyboard shortcuts in a game's right-click menu", isOn: $model.settings.showMenuShortcuts)
            }
            Section("Game controller") {
                if model.gamepad.controllerNames.isEmpty {
                    Text("No controller connected")
                } else {
                    // Two controllers of one model have the same name.
                    ForEach(Array(model.gamepad.controllerNames.enumerated()), id: \.offset) { Text($0.element) }
                }
                Text("Help › Keyboard Shortcuts shows what each button does.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                if model.updater.isAvailable {
                    @Bindable var updater = model.updater
                    Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
                    Text("Once a day, \(AppInfo.displayName) asks getsilverbox.app for the newest version.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("This copy was built from its source code, so it does not check for updates.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .withoutInitialFocus()
    }
}

struct LibrarySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingLocalPicker = false

    /// A whole drive or the home folder gets a "Silverbox" folder of its
    /// own, so the app's folders do not land at the root.
    static func dataFolder(for chosen: URL) -> URL {
        let url = chosen.standardizedFileURL
        let isVolumeRoot = url.pathComponents.count == 3 && url.pathComponents[1] == "Volumes"
        let isHome = url == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        return isVolumeRoot || isHome || url.path == "/"
            ? url.appendingPathComponent("Silverbox", isDirectory: true) : url
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Collections") {
                ForEach($model.settings.collections) { $collection in
                    CollectionEditor(collection: $collection)
                }
                if model.collections.isEmpty {
                    Text("No collections yet.").foregroundStyle(.secondary)
                }
                HStack {
                    Button("Add Collection…") { model.chooseCollection() }
                    if let name = model.folderBeingRead {
                        ProgressView().controlSize(.small)
                        Text("Reading \(name)…").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let library = model.library, let titles = model.sidebarCounts.scopes[.all] {
                        Text(
                            "\(titles.formatted()) titles in \(library.snapshots.count) collection\(library.snapshots.count == 1 ? "" : "s")"
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button("Rescan All") { model.reloadLibrary(clearMediaCache: true) }
                        .disabled(model.collections.isEmpty)
                        .help(
                            model.collections.isEmpty
                                ? "Add a collection first" : "Read every collection again, with its images and media")
                }
                Text("A collection is an eXo download or any LaunchBox library folder. You can also drop one here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local data folder") {
                HStack {
                    Picker("Keep data in", selection: dataFolderBinding) {
                        Text("The default folder").tag(DataFolderChoice.standard)
                        if let custom = model.settings.localStorePath {
                            Text(shownPath(custom.replacingOccurrences(of: NSHomeDirectory(), with: "~")))
                                .tag(DataFolderChoice.custom)
                        }
                        Divider()
                        Text("Other…").tag(DataFolderChoice.other)
                    }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.localStore.directory])
                    }
                    .disabled(!dataFolderExists)
                    .help(dataFolderExists ? model.localStore.directory.path : "The folder is not there yet")
                }
                // On this row alone, so that its message stays out of the collections' folder dialogs.
                .fileImporter(isPresented: $showingLocalPicker, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        let folder = Self.dataFolder(for: url)
                        try? LocalStore(directory: folder).ensureDirectories()
                        model.setDataFolder(folder.path)
                    }
                }
                .fileDialogMessage("Choose the folder for installed games, saves and caches.")
                .fileDialogConfirmationLabel("Choose")
                if model.settings.localStorePath != nil, !dataFolderExists {
                    if AppModel.volumeIsMissing(for: model.localStore.directory) {
                        StatusLabel(
                            "The drive with this folder is not connected. Installs, soundtracks and caches wait for it.",
                            tone: .warning
                        )
                        .font(.caption)
                    } else {
                        Text("\(AppInfo.displayName) makes this folder when it first needs it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(
                    "Installed games, saves and caches are kept here, so a collection can stay read-only. Choosing another folder does not move what is there."
                )
                .font(.caption).foregroundStyle(.secondary)
                Picker("Install games to", selection: $model.settings.installLocation) {
                    ForEach(InstallLocation.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Game downloads") {
                DownloaderStatus()
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .watchingForEmulators()
        .withoutInitialFocus()
        .dropDestination(for: URL.self) { urls, _ in
            model.addDroppedFolders(urls)
        }
    }

    /// The pop-up's entries: the default folder, the chosen one, and
    /// "Other…", which is never the selection: it opens the folder chooser.
    private enum DataFolderChoice: Hashable { case standard, custom, other }

    private var dataFolderExists: Bool {
        FileManager.default.fileExists(atPath: model.localStore.directory.path)
    }

    private var dataFolderBinding: Binding<DataFolderChoice> {
        Binding(
            get: { model.settings.localStorePath == nil ? .standard : .custom },
            set: { choice in
                switch choice {
                case .standard: model.setDataFolder(nil)
                case .custom: break
                // After the menu has closed.
                case .other: DispatchQueue.main.async { showingLocalPicker = true }
                }
            }
        )
    }
}

/// One collection: name, folder, enabled, path substitutions and what was found.
struct CollectionEditor: View {
    @Binding var collection: LibraryCollection
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var pickingRoot = false
    @State private var pickingSubstitution: UUID?
    @State private var confirmingRemoval = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        TextField("Name", text: $collection.name)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    }
                    GridRow {
                        Text("Folder").foregroundStyle(.secondary)
                        HStack {
                            Text(shownPath(collection.rootPath)).font(Theme.mono).lineLimit(1).truncationMode(.middle)
                                .help(collection.rootPath)
                            Spacer()
                            Button("Choose…") { pickingRoot = true }
                        }
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Toggle("Show in the library", isOn: $collection.isEnabled)
                            .toggleStyle(.checkbox)
                    }
                }
                if let error = model.loadErrors[collection.id] {
                    HStack {
                        StatusLabel(error, tone: .bad).font(.caption)
                        Spacer()
                        Button(model.disconnectedShares.isEmpty ? "Try Again" : "Connect") { model.tryAgain() }
                            .help(
                                model.disconnectedShares.isEmpty
                                    ? "Load the collections again."
                                    : "Connect to the network shares that are gone, then load the collections again.")
                    }
                }
                if let report = model.rootReports[collection.id] {
                    LibraryRootReportDisclosure(report: report)
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
                            Text(substitution.macPath.isEmpty ? "Choose a folder" : shownPath(substitution.macPath))
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
                Divider()
                HStack {
                    Text("Removing a collection deletes nothing: its folder, and the games installed from it, stay.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove Collection…", role: .destructive) { confirmingRemoval = true }
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                Text(collection.name).fontWeight(.semibold)
                if !collection.isEnabled { Text("(disabled)").foregroundStyle(.secondary) }
                Spacer()
                if let subtitle = model.sidebarCounts.collections[collection.id] {
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Remove “\(collection.name)” from \(AppInfo.displayName)?", isPresented: $confirmingRemoval)
        {
            Button("Remove", role: .destructive) { model.removeCollection(id: collection.id) }
        } message: {
            Text("The collection's folder stays as it is, and so do the games installed from it. You can add it again.")
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
                    "eXoDOS names a DOSBox build for each game. “Match” runs its Daum and DOSBox-X games in DOSBox-X, and the rest in DOSBox Staging."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(EmulatorKind.dosBox) { kind in
                Section(kind.displayName) {
                    EmulatorPathRow(kind: kind, picking: $picking)
                    if kind == .dosboxStaging { FluidSynthStatus() }
                }
            }
            Section("eXoWin9x games") {
                Text("eXoWin9x games start Windows 98 in DOSBox-X. About thirty need 86Box, for its 3dfx Voodoo card.")
                    .font(.caption).foregroundStyle(.secondary)
                // 86Box alone is not enough: without this line, its "Ready" reads as an all-clear.
                if model.emulatorInstallation(.dosboxX)?.exists != true {
                    StatusLabel("DOSBox-X is not installed. The other eXoWin9x games need it.", tone: .warning)
                        .font(.callout)
                }
                EmulatorPathRow(kind: .box86, picking: $picking)
            }
            Section("eXoScummVM games") {
                Text("Saves and settings for these games are kept apart from your own ScummVM's.")
                    .font(.caption).foregroundStyle(.secondary)
                EmulatorPathRow(kind: .scummVM, picking: $picking)
                Text("A few games need an engine that only ScummVM's daily builds have. Choose one here for them.")
                    .font(.caption).foregroundStyle(.secondary)
                EmulatorPathRow(kind: .scummVMDaily, picking: $picking)
            }
            Section("eXoIF games") {
                Text(
                    "Story files open in Spatterlight, MS-DOS versions run in DOSBox, and 8-bit computer versions run in RetroArch."
                )
                .font(.caption).foregroundStyle(.secondary)
                EmulatorPathRow(kind: .spatterlight, picking: $picking)
            }
            Section("eXoAppleIIGS games") {
                Text("Most eXoAppleIIGS games run in GSplus, with the Apple IIGS ROM that eXo ships.")
                    .font(.caption).foregroundStyle(.secondary)
                EmulatorPathRow(kind: .gsplus, picking: $picking)
                AppleIIGSROMRow()
            }
            Section("Consoles, computers and arcade") {
                Text(
                    "Games from a LaunchBox library start in their platform's emulator: your choice under Platforms, else the library's own, matched to the Mac emulators found here."
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
        .withoutInitialFocus()
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
        .watchingForEmulators()
    }

    @ViewBuilder
    private var retroArchCoresRow: some View {
        let setup = model.retroArchSetup
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cores folder").font(.subheadline)
                Text(
                    setup?.coresDirectory.map { shownPath($0.path) }
                        ?? (setup == nil ? "RetroArch is not installed" : "Not found")
                )
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

/// One emulator: the app that was found, with its icon and version, or what
/// its absence costs and where to get it; Choose and Auto-detect beside it.
struct EmulatorPathRow: View {
    let kind: EmulatorKind
    @Binding var picking: EmulatorKind?
    @Environment(AppModel.self) private var model

    var body: some View {
        let installation = model.emulatorInstallation(kind)
        let found = installation?.exists == true
        let blocked = model.isBlockedByMacOS(kind)
        VStack(alignment: .leading, spacing: 8) {
            row(installation: installation, found: found, blocked: blocked)
            if found, blocked {
                // What to do, in the order to do it. macOS shows Open Anyway only after it has
                // stopped the app once.
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        "Apple has not checked this app, so macOS stops it the first time. Open it once, then click Open Anyway in Privacy & Security."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Open \(kind.displayName)") { model.openEmulatorOnce(kind) }
                    Button("Privacy & Security…") { model.openPrivacyAndSecurity() }
                }
                .controlSize(.small)
            }
        }
    }

    private func row(installation: EmulatorInstallation?, found: Bool, blocked: Bool) -> some View {
        HStack(spacing: 10) {
            if let installation, found {
                let app = EmulatorApp(installation)
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name + (app.version.map { " \($0)" } ?? ""))
                    if blocked {
                        StatusLabel("macOS has not allowed it yet", tone: .warning, textStyle: Theme.textSecondary)
                            .font(.caption)
                    } else {
                        StatusLabel("Ready", tone: .good, textStyle: Theme.textSecondary).font(.caption)
                    }
                }
                .help(installation.executableURL.path)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installation == nil ? "\(kind.displayName) is not installed" : "The chosen file is gone")
                    HStack(spacing: 8) {
                        if let cost = model.gamesNeedingLine(kind) {
                            Text(cost).foregroundStyle(.secondary).help(model.gamesNeedingBreakdown(kind))
                        }
                        if let url = URL(string: kind.website) {
                            Link("Get it from \(url.host ?? kind.website)", destination: url).accentLink()
                        }
                    }
                    .font(.caption)
                }
                .help(installation?.executableURL.path ?? "")
            }
            Spacer()
            Button("Choose…") { picking = kind }
            if model.settings.emulatorPath(for: kind) != nil {
                Button("Auto-detect") { model.settings.setEmulatorPath(nil, for: kind) }
            }
        }
    }
}

/// An emulator as the user knows it: the app's name, icon and version, not
/// the path of the executable inside it.
struct EmulatorApp {
    let name: String
    let version: String?
    let icon: NSImage

    init(_ installation: EmulatorInstallation) {
        if let app = installation.appBundleURL {
            name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
            version = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            icon = NSWorkspace.shared.icon(forFile: app.path)
        } else {
            // A command-line program, such as Homebrew's: its Cellar folder names the version.
            let resolved = installation.executableURL.resolvingSymlinksInPath()
            name = installation.kind.displayName
            let parts = resolved.pathComponents
            version = parts.firstIndex(of: "Cellar").flatMap { parts.indices.contains($0 + 2) ? parts[$0 + 2] : nil }
            icon = NSWorkspace.shared.icon(forFile: resolved.path)
        }
    }
}

/// One row per platform with ROM games: which emulator and core run it.
struct PlatformAssignmentsView: View {
    @Environment(AppModel.self) private var model
    @State private var onlyProblems = false
    @State private var filter = ""

    var body: some View {
        let resolver = model.emulatorResolver()
        let cores = model.retroArchSetup?.installedCores() ?? []
        if model.romPlatforms.isEmpty {
            Text("No console, computer or arcade platforms are loaded. Add a LaunchBox library in the Library tab.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            let rows = model.romPlatforms.map { (platform: $0, resolved: resolver.resolve(platform: $0.name)) }
            let problems = rows.count { !$0.resolved.isReady }
            let shown = rows.filter {
                (!onlyProblems || !$0.resolved.isReady)
                    && (filter.isEmpty || $0.platform.name.localizedCaseInsensitiveContains(filter))
            }
            HStack {
                Picker("Show", selection: $onlyProblems) {
                    Text("All \(rows.count)").tag(false)
                    Text("Not ready (\(problems))").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                TextField("Filter platforms", text: $filter)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            if shown.isEmpty {
                Text(onlyProblems && problems == 0 ? "Every platform is ready." : "No platform matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.platform.id) { row in
                PlatformAssignmentRow(platform: row.platform, resolved: row.resolved, cores: cores)
            }
        }
    }
}

struct PlatformAssignmentRow: View {
    let platform: AppModel.RomPlatformSummary
    let resolved: ResolvedEmulatorAssignment
    let cores: [RetroArchCore]
    @Environment(AppModel.self) private var model
    @State private var showingOptions = false

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
                // The core's column stays, empty, for the other emulators, so the rows line up.
                Group {
                    if effectiveKind == .retroArch {
                        Picker("Core", selection: coreBinding) {
                            Text("Choose a core").tag(String?.none)
                            ForEach(missingCores, id: \.self) { Text("\($0) (missing)").tag(String?.some($0)) }
                            ForEach(cores) { Text($0.title).tag(String?.some($0.name)) }
                        }
                        .labelsHidden()
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(width: 220)
                Button {
                    showingOptions = true
                } label: {
                    Image(
                        systemName: userAssignment?.arguments.isEmpty == false
                            ? "ellipsis.circle.fill" : "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .disabled(userAssignment == nil)
                .help(
                    userAssignment == nil
                        ? "Choose an emulator first. Automatic takes the library's arguments."
                        : "Extra arguments for the emulator"
                )
                .popover(isPresented: $showingOptions, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Extra arguments for \(platform.name)").font(.headline)
                        TextField("Extra arguments", text: argumentsBinding)
                            .labelsHidden()
                            .font(Theme.mono)
                            .textFieldStyle(.roundedBorder)
                        Text(
                            "Added to the emulator's command line, before the game. Put a value with spaces in double quotes."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(width: 360)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                StatusLabel(status, tone: resolved.isReady ? .good : .warning, textStyle: Theme.textSecondary)
                    .font(.caption)
                Spacer()
                fix
            }
        }
        .padding(.vertical, 2)
    }

    /// What to do about a platform that is not ready: get the emulator, or
    /// open RetroArch to download the core.
    @ViewBuilder private var fix: some View {
        if !resolved.isReady, let kind = resolved.assignment?.emulator {
            if let installation = model.emulatorInstallation(kind), installation.exists {
                if kind == .retroArch, let app = installation.appBundleURL {
                    Button("Open RetroArch") {
                        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                    }
                    .controlSize(.small)
                    .help("Download the core in RetroArch: Online Updater › Core Downloader.")
                }
            } else if let url = URL(string: kind.website) {
                Link("Get \(kind.displayName)", destination: url).font(.caption).accentLink()
            }
        }
    }

    private var detail: String {
        var text = platform.gameCount == 1 ? "1 game" : "\(platform.gameCount.formatted()) games"
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
                Text("Automatic lets DOSBox Staging size the window; DOSBox-X uses the size in the game's config.")
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
                FluidSynthStatus()
                Text("Games set up for the Roland MT-32 always use the MT-32 emulation with the ROMs in eXo/mt32.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .watchingForEmulators()
        .withoutInitialFocus()
    }
}

/// Whether DOSBox Staging can play General MIDI through FluidSynth, and
/// what to do when it cannot. The emulator check follows an update or a
/// Homebrew install while Settings is open.
struct FluidSynthStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.emulatorInstallation(.dosboxStaging)?.exists == true {
            let available = model.fluidSynthAvailable
            VStack(alignment: .leading, spacing: 4) {
                StatusLabel(
                    available ? "FluidSynth ready in DOSBox Staging" : "No FluidSynth in DOSBox Staging",
                    tone: available ? .good : .warning)
                Text(
                    available
                        ? "General MIDI games play with the eXoDOS Sound Canvas SoundFont."
                        : "General MIDI games use the macOS synthesizer instead. Update DOSBox Staging to 0.83 or later, or install FluidSynth: brew install fluid-synth."
                )
                .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}

/// Whether aria2 is there to download the games a Lite collection leaves out.
struct DownloaderStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let downloader = model.torrentDownloader
        VStack(alignment: .leading, spacing: 4) {
            StatusLabel(
                downloader == nil ? "aria2 is not installed" : "aria2 ready",
                tone: downloader == nil ? .warning : .good
            )
            .help(downloader?.executable.path ?? "")
            Text(
                "aria2 downloads each game of an eXo Lite collection from the eXo torrent when you install it."
                    + (downloader == nil ? " Install it with Homebrew: brew install aria2." : "")
            )
            .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

/// The Apple IIGS character ROM that current MAME needs for the 74
/// eXoAppleIIGS games eXo runs in MAME: found, or a button to add it.
struct AppleIIGSROMRow: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false

    var body: some View {
        let found = model.hasAppleIIGSROM
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusLabel(
                    found ? "Apple IIGS ROM for MAME added" : "Apple IIGS ROM for MAME missing",
                    tone: found ? .good : .warning)
                Spacer()
                Button(found ? "Replace…" : "Add ROM…") { picking = true }
            }
            Text(
                "eXo runs 74 games in MAME, which needs one ROM that eXo's set lacks: \(AppleIIGSCharacterROM.fileName). Choose the file, or a zip that holds it, such as apple2gs.zip from a current MAME ROM set."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .zip]) { result in
            if case .success(let url) = result { model.importAppleIIGSROM(from: url) }
        }
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
                    .fill(isSelected ? Theme.accent.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// Looks for the emulators every two seconds while the view is shown, so
    /// one installed meanwhile shows up without a restart.
    func watchingForEmulators() -> some View {
        modifier(EmulatorWatcher())
    }
}

private struct EmulatorWatcher: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                model.checkEmulators()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
