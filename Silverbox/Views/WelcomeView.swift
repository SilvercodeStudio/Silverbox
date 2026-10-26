import SwiftUI
import UniformTypeIdentifiers
import SilverboxCore

/// The library window before any collection is added: the two kinds of
/// folder the app takes, and the emulators each eXo pack needs, each found
/// or with a link to get it. The emulators are looked for every two
/// seconds, so one installed meanwhile shows as found.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @State private var showingPicker = false

    /// The emulators to name, the packs each one plays, and whether the main
    /// packs need it.
    private static let emulators: [(kind: EmulatorKind, use: String, needed: Bool)] = [
        (.dosboxStaging, "eXoDOS, eXoWin3x and eXoDemoScene games", true),
        (.dosboxX, "eXoWin9x games, and the eXoDOS games made for it", true),
        (.box86, "About thirty eXoWin9x games that need a 3dfx Voodoo card", false),
        (.scummVM, "eXoScummVM games", false),
        (.spatterlight, "eXoIF text adventures", false),
        (.retroArch, "eXoIF's 8-bit computer versions, and consoles in a LaunchBox library", false),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                CRTHero(icon: model.settings.appIcon.image, height: 210, iconSize: 160)
                Theme.accent.frame(height: 3)
                content
            }
        }
        .watchingForEmulators()
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addFolder(url) }
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Welcome to \(AppInfo.displayName)")
                    .font(.system(size: 30, weight: .bold))
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
                    Button("Add Collection…") { showingPicker = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.accentText)
                        .controlSize(.large)
                }
            }
            step(2, "Install the emulators") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Games run in Mac emulators that you install yourself. eXoDOS needs DOSBox Staging; the others are for the other packs. aria2 is not an emulator: it downloads the games that eXoDOS Lite leaves out."
                    )
                    VStack(spacing: 0) {
                        ForEach(Self.emulators, id: \.kind) { item in
                            emulatorRow(item.kind, use: item.use, needed: item.needed)
                            Divider()
                        }
                        row(
                            "aria2", use: "Downloads each game of eXoDOS Lite (brew install aria2)", needed: false,
                            found: model.torrentDownloader != nil, website: "https://aria2.github.io")
                    }
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
            }
            VStack(spacing: 8) {
                Text(
                    "Installed games, saves and caches go to the local data folder, \(model.localStore.directory.path). To keep them on another drive, choose that folder in Library Settings before you install anything."
                )
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Library Settings…") {
                    SettingsState.shared.show(tab: .library)
                    openSettings()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: 560)
        .padding(32)
        .frame(maxWidth: .infinity)
    }

    private func step(_ number: Int, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
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
            Image(systemName: systemImage).foregroundStyle(Theme.accent)
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
            Image(systemName: found ? "checkmark.circle.fill" : needed ? "exclamationmark.circle" : "circle")
                .foregroundStyle(found ? Theme.good : needed ? Theme.warning : Theme.textTertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body.weight(.medium))
                Text(use).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if found {
                Text("Found").font(.callout).foregroundStyle(Theme.good)
            } else if let url = URL(string: website) {
                Link("Get \(name)", destination: url).font(.callout)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
    }
}
