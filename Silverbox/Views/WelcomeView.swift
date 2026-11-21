import SwiftUI
import UniformTypeIdentifiers
import SilverboxCore

/// The library window before any collection is added: the two kinds of
/// folder the app takes, where installed games go, and the emulators eXoDOS
/// needs, each found or with a link to get it; the other packs' emulators
/// are behind a disclosure. The emulators are looked for every two seconds,
/// so one installed meanwhile shows as found.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingDataPicker = false
    @State private var showingOtherPacks = false

    /// What eXoDOS needs, and what the other packs need.
    private static let main: [(kind: EmulatorKind, use: String, needed: Bool)] = [
        (.dosboxStaging, "Runs eXoDOS, eXoWin3x and eXoDemoScene games", true),
        (.dosboxX, "Runs eXoWin9x games, and the eXoDOS games made for it", false),
    ]
    private static let others: [(kind: EmulatorKind, use: String, needed: Bool)] = [
        (.box86, "About thirty eXoWin9x games that need a 3dfx Voodoo card", false),
        (.scummVM, "eXoScummVM games", false),
        (.spatterlight, "eXoIF text adventures", false),
        (.gsplus, "eXoAppleIIGS games", false),
        (.retroArch, "eXoIF's 8-bit computer versions, and consoles in a LaunchBox library", false),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CRTHero(variant: model.settings.appIcon, height: 210, iconSize: 160)
                content
            }
        }
        .watchingForEmulators()
        .withoutInitialFocus()
    }

    private var content: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Welcome to \(AppInfo.displayName)")
                    .font(Theme.display(size: 48))
                Text("Browse and play the eXo game collections on your Mac.")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            step(1, "Add a collection") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose a folder, or drop it on this window. Either kind works:")
                    bullet(
                        "shippingbox",
                        "**An eXo download, as it came**, such as eXoDOS or eXoDOS Lite from its torrent. \(AppInfo.displayName) sets it up as eXo's setup does on Windows."
                    )
                    bullet(
                        "folder",
                        "**A collection that is already set up**, on Windows or on this Mac, or any LaunchBox library folder."
                    )
                    Text(
                        "The folder can be read-only, on another drive or on a network share. \(AppInfo.displayName) never changes it."
                    )
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        Button {
                            model.chooseCollection()
                        } label: {
                            Text("Add Collection…").foregroundStyle(Theme.accentText)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                        .disabled(model.folderBeingRead != nil)
                        if let name = model.folderBeingRead {
                            ProgressView().controlSize(.small)
                            Text("Reading \(name)…").foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            // The default folder needs no choice, so the step is done unless a chosen folder is out of reach.
            step(2, "Choose where installed games go", done: dataFolderReady) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Installed games, saves and caches go to the local data folder. Choose it before you install anything: a change later does not move what is there."
                    )
                    HStack(spacing: 10) {
                        Label(
                            model.localStore.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                            systemImage: "folder"
                        )
                        .font(Theme.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.localStore.directory.path)
                        Spacer()
                        if model.settings.localStorePath != nil {
                            Button("Use Default") { model.setDataFolder(nil) }
                        }
                        Button("Choose…") { showingDataPicker = true }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .fileImporter(isPresented: $showingDataPicker, allowedContentTypes: [.folder]) { result in
                    if case .success(let url) = result {
                        let folder = LibrarySettingsView.dataFolder(for: url)
                        try? LocalStore(directory: folder).ensureDirectories()
                        model.setDataFolder(folder.path)
                    }
                }
                .fileDialogMessage("Choose the folder for installed games, saves and caches.")
                .fileDialogConfirmationLabel("Choose")
                if !dataFolderReady {
                    StatusLabel("The drive with this folder is not connected.", tone: .warning).font(.callout)
                }
            }
            step(3, "Check your emulators", done: model.emulatorInstallation(.dosboxStaging)?.exists == true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Games run in Mac emulators that you install yourself. eXoDOS needs DOSBox Staging.")
                    VStack(spacing: 0) {
                        ForEach(Self.main, id: \.kind) { item in
                            emulatorRow(item.kind, use: item.use, needed: item.needed)
                            Divider()
                        }
                        row(
                            "aria2",
                            use: model.torrentDownloader == nil
                                ? "Downloads each game of eXoDOS Lite. Install it with Homebrew: brew install aria2"
                                : "Downloads each game of eXoDOS Lite",
                            needed: false, found: model.torrentDownloader != nil, website: "https://aria2.github.io")
                    }
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    DisclosureGroup("For the other packs", isExpanded: $showingOtherPacks) {
                        VStack(spacing: 0) {
                            ForEach(Array(Self.others.enumerated()), id: \.element.kind) { offset, item in
                                if offset > 0 { Divider() }
                                emulatorRow(item.kind, use: item.use, needed: item.needed)
                            }
                        }
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        .padding(.top, 6)
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    /// True for the default folder, and for a chosen one that is there.
    private var dataFolderReady: Bool {
        model.settings.localStorePath == nil
            || FileManager.default.fileExists(atPath: model.localStore.directory.path)
    }

    /// A numbered step; the number becomes a checkmark when the step is done.
    private func step(_ number: Int, _ title: String, done: Bool = false, @ViewBuilder content: () -> some View)
        -> some View
    {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                        .accessibilityLabel("Step \(number), done")
                } else {
                    Text("\(number)").font(.system(size: 15, weight: .bold))
                }
            }
            .foregroundStyle(done ? Theme.window : Theme.accentText)
            .frame(width: 28, height: 28)
            .background(done ? Theme.good : Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.textSecondary)
        }
    }

    /// One emulator: found, or a link to its website.
    private func emulatorRow(_ kind: EmulatorKind, use: String, needed: Bool) -> some View {
        row(
            kind.displayName, use: use, needed: needed, found: model.emulatorInstallation(kind)?.exists == true,
            website: kind.website)
    }

    private func row(_ name: String, use: String, needed: Bool, found: Bool, website: String) -> some View {
        HStack(spacing: 10) {
            Group {
                if found || needed {
                    StatusGlyph(tone: found ? .good : .warning)
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(use).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if found {
                Text("Found").font(.callout).foregroundStyle(Theme.textSecondary)
            } else if let url = URL(string: website) {
                Link("Get \(name)", destination: url).font(.callout).accentLink()
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
    }
}
