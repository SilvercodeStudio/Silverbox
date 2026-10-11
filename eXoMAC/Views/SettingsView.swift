import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            LibrarySettingsView()
                .tabItem { Label("Library", systemImage: "folder") }
            EmulatorSettingsView()
                .tabItem { Label("Emulators", systemImage: "display") }
            DisplaySettingsView()
                .tabItem { Label("Display & Sound", systemImage: "tv.and.hifispeaker.fill") }
        }
        .frame(width: 640)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Menu music") {
                Toggle("Play a game's music while browsing", isOn: $model.settings.musicEnabled)
                Slider(value: $model.settings.musicVolume, in: 0...1) { Text("Volume") }
                Text("Ogg Vorbis tracks are not supported by macOS and are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Playing") {
                Toggle("Show launch options before each game", isOn: $model.settings.showLaunchOptions)
                Text("The dialog offers the game's versions, full screen or window, shader or filter, and emulator, like the menus eXoDOS shows in its console window. Configure in a game's menu opens the same dialog to save choices for that game.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Library view") {
                Toggle("Show hidden games", isOn: $model.settings.showHiddenGames)
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
                        Text("\(library.games.count.formatted()) games in \(library.snapshots.count) collection\(library.snapshots.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                    Button("Rescan All") { model.reloadLibrary(clearMediaCache: true) }
                        .disabled(model.collections.isEmpty)
                }
                Text("A collection is an eXoDOS install or any LaunchBox library folder. Rescan after you add or update packs.")
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
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.localStore.directory]) }
                }
                Text("Installed games, save backups, edited configs and logs are kept here, so the collections can stay read-only.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Install games to", selection: $model.settings.installLocation) {
                    ForEach(InstallLocation.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addCollection(url: url) }
        }
        .fileImporter(isPresented: $showingLocalPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.settings.localStorePath = url.path }
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
                    Text("Map a Windows prefix used in the library, such as X:\\Emulation or the Games folder, to a folder on this Mac.")
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
                            } label: { Image(systemName: "minus.circle") }
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
        .fileImporter(isPresented: Binding(get: { pickingSubstitution != nil }, set: { if !$0 { pickingSubstitution = nil } }),
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result, let id = pickingSubstitution,
               let index = collection.substitutions.firstIndex(where: { $0.id == id }) {
                collection.substitutions[index].macPath = url.path
            }
            pickingSubstitution = nil
        }
    }
}

struct EmulatorSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var picking: EmulatorKind?

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Which emulator to use") {
                Picker("Default", selection: $model.settings.emulatorPolicy) {
                    ForEach(EmulatorPolicy.allCases) { Text($0.displayName).tag($0) }
                }
                Text("eXoDOS picks a DOSBox build per game (0.74, ECE, Staging, SVN Daum or DOSBox-X). “Match” maps Daum and DOSBox-X games to DOSBox-X and everything else to DOSBox Staging. You can override any game in its info sheet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(EmulatorKind.allCases) { kind in
                Section(kind.displayName) {
                    let installation = model.settings.emulatorInstallation(kind)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(installation?.executableURL.path ?? "Not found")
                                .font(Theme.mono)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let installation {
                                Label(installation.exists ? "Ready" : "Executable missing", systemImage: installation.exists ? "checkmark.circle.fill" : "xmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(installation.exists ? Theme.accent : .red)
                            }
                        }
                        Spacer()
                        Button("Choose…") { picking = kind }
                        if path(for: kind) != nil {
                            Button("Auto-detect") { setPath(nil, for: kind) }
                        }
                    }
                    if kind == .dosboxStaging, let installation {
                        Text(EmulatorCapabilities.fluidSynthAvailable(for: installation)
                             ? "FluidSynth is available for General MIDI with the eXoDOS Sound Canvas SoundFont."
                             : "FluidSynth is not installed, so General MIDI games use the macOS synthesizer. Install it with Homebrew (brew install fluid-synth) for the eXoDOS SoundFont.")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .fileImporter(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
                      allowedContentTypes: [.applicationBundle, .unixExecutable]) { result in
            if case .success(let url) = result, let kind = picking {
                setPath(url.path, for: kind)
            }
            picking = nil
        }
    }

    private func path(for kind: EmulatorKind) -> String? {
        switch kind {
        case .dosboxStaging: return model.settings.stagingExecutablePath
        case .dosboxX: return model.settings.dosboxXExecutablePath
        }
    }

    private func setPath(_ path: String?, for kind: EmulatorKind) {
        switch kind {
        case .dosboxStaging: model.settings.stagingExecutablePath = path
        case .dosboxX: model.settings.dosboxXExecutablePath = path
        }
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
                Text("Automatic lets DOSBox Staging size the window for your screen. DOSBox-X then uses the size in the game's config, which eXoDOS sets for a 1080p desktop.")
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
