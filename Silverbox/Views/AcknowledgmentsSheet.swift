import SwiftUI
import SilverboxCore

/// A license text bundled with the app, from `Silverbox/Licenses/`.
enum BundledLicense {
    static func text(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "The license file \(name).txt is missing from the app." }
        return text
    }
}

/// Who made what the app builds on: the eXo team's collections, the
/// emulators it starts, and the two decoders it includes, with their
/// licenses.
struct AcknowledgmentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private static let libraries: [(name: String, authors: String, file: String, url: String)] = [
        (
            "stb_vorbis", "Sean Barrett", "stb_vorbis",
            "https://github.com/nothings/stb"
        ),
        (
            "libxmp-lite", "Claudio Matsuoka and Hipolito Carraro Jr", "libxmp-lite",
            "https://github.com/libxmp/libxmp"
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Acknowledgments").font(.headline).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("The collections") {
                        Text(
                            "eXoDOS, eXoWin3x, eXoWin9x, eXoDemoScene, eXoScummVM, eXoAppleIIGS and eXoIF are the work of the eXo team: the games, the metadata, the box art and the launch settings that \(AppInfo.displayName) reads. Nothing of theirs is included in this app."
                        )
                        Link("retro-exo.com", destination: AboutPanel.projectURL)
                    }
                    section("The emulators") {
                        Text(
                            "Games run in emulators you install yourself; \(AppInfo.displayName) only starts them with the right settings."
                        )
                        ForEach(EmulatorKind.allCases, id: \.self) { kind in
                            if let url = URL(string: kind.website) {
                                HStack {
                                    Text(kind.displayName)
                                    Spacer()
                                    Link(url.host ?? kind.website, destination: url).font(.caption)
                                }
                            }
                        }
                    }
                    section("Included software") {
                        ForEach(Self.libraries, id: \.name) { library in
                            DisclosureGroup {
                                Text(BundledLicense.text(named: library.file))
                                    .font(Theme.mono)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                            } label: {
                                HStack {
                                    Text("\(library.name), by \(library.authors). MIT license.")
                                    Spacer()
                                    if let url = URL(string: library.url) {
                                        Link(url.host ?? library.url, destination: url).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 520)
        .background(Theme.window)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The app's own license, from the bundled copy of the LICENSE file.
struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("License").font(.headline).padding(20)
            Divider()
            ScrollView {
                Text(BundledLicense.text(named: "Silverbox"))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 560, height: 460)
        .background(Theme.window)
    }
}
