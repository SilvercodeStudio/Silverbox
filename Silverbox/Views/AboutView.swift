import SwiftUI
import SilverboxCore

/// The About panel's facts, shared with the menus and the acknowledgments.
enum AboutPanel {
    static let productName = AppInfo.displayName
    static let projectURL = URL(string: "https://www.retro-exo.com")!

    /// "Version 0.5". The commit of the build is in the line's help and in
    /// what a click copies, not in the window.
    static var version: String { "Version \(AppInfo.version)" }

    /// What the version line's help says: the commit, and that a click copies.
    static var versionHelp: String {
        (AppInfo.commit.map { "Commit \($0). " } ?? "") + "Click to copy the version."
    }

    /// "© 2026 Preston Landers · Silvercode Studio", with a link to the studio. The copyright
    /// stays the author's, as in NOTICE; the studio's name comes after it.
    static var copyrightLine: AttributedString {
        let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
        var studio = AttributedString("Silvercode Studio")
        studio.link = SilverboxLinks.studio
        return AttributedString(copyright.isEmpty ? "" : "\(copyright) · ") + studio
    }
}

/// The About window, laid out like Silverside's: the icon on a CRT band, the
/// accent under it, the name and version, what the library holds, the eXo
/// credit with the eXoDOS cover, and the buttons.
struct AboutView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAcknowledgments = false
    @State private var copiedVersion = false

    var body: some View {
        VStack(spacing: 0) {
            CRTHero(variant: model.settings.appIcon)
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    Text(AboutPanel.productName).font(Theme.display(size: 56))
                    Text(copiedVersion ? "Copied" : AboutPanel.version)
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                        .help(AboutPanel.versionHelp)
                        .onTapGesture { copyVersion() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(AboutPanel.versionHelp)
                }
                Text("Browse and play the eXo collections on your Mac.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                stats
                eXoCredit
                Text(
                    "Games run in DOSBox Staging, DOSBox-X, ScummVM, RetroArch and the other emulators listed in Acknowledgments."
                )
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Acknowledgments…") { showingAcknowledgments = true }
                    Button("Website") { NSWorkspace.shared.open(AppInfo.websiteURL) }
                    Button("Leave a Tip") { NSWorkspace.shared.open(SilverboxLinks.sponsor) }
                }
                .controlSize(.large)
                .padding(.top, 6)
                Text(AboutPanel.copyrightLine).font(.callout).foregroundStyle(Theme.textSecondary)
                    .tint(Theme.accent)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .frame(width: 460)
        .background(Theme.window)
        .withoutInitialFocus()
        .sheet(isPresented: $showingAcknowledgments) { AcknowledgmentsSheet() }
    }

    /// Copies "Silverbox 0.5 · c2b2f09", the line a problem report starts with.
    private func copyVersion() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppInfo.versionLine, forType: .string)
        copiedVersion = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copiedVersion = false
        }
    }

    /// What the library holds, once it has loaded. Played counts only when
    /// something has been played.
    @ViewBuilder private var stats: some View {
        let counts = model.sidebarCounts.scopes
        if let games = counts[.all], games > 0 {
            let installed = counts[.installed] ?? 0
            let played = counts[.recentlyPlayed] ?? 0
            HStack(spacing: 10) {
                StatTile(value: games, label: games == 1 ? "game" : "games")
                StatTile(value: installed, label: "installed")
                if played > 0 { StatTile(value: played, label: "played") }
            }
        }
    }

    /// The eXo team's credit beside the eXoDOS 6 cover.
    private var eXoCredit: some View {
        HStack(alignment: .center, spacing: 14) {
            Image("eXoDOSCover")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("The eXo collections are projects of the eXo team.")
                    .fixedSize(horizontal: false, vertical: true)
                Link(
                    AboutPanel.projectURL.host() ?? AboutPanel.projectURL.absoluteString,
                    destination: AboutPanel.projectURL
                )
                .accentLink()
                Text("eXoDOS 6: Forever Voyaging")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
            .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.textSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The app icon on a dark CRT screen, for the About window and the welcome:
/// the website's band, with scanlines, a glow behind the icon and a darker
/// edge, over a rule. The glow and the rule are amber or green with the
/// chosen icon (`AppIconVariant.phosphor`). It stays dark in the light
/// appearance, as Silverside's hero does.
struct CRTHero: View {
    let variant: AppIconVariant
    var height: CGFloat = 232
    var iconSize: CGFloat = 190

    var body: some View {
        VStack(spacing: 0) {
            screen
            variant.phosphor.glow.frame(height: 3)
        }
    }

    private var screen: some View {
        Image(nsImage: variant.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Only the background reaches under the title bar, so the window keeps its height. The glow
            // centers on the icon, measured from the bottom.
            .background {
                Canvas { context, size in
                    let bounds = Path(CGRect(origin: .zero, size: size))
                    let center = CGPoint(x: size.width / 2, y: size.height - height / 2)
                    context.fill(bounds, with: .color(variant.phosphor.ground))
                    context.fill(
                        bounds,
                        with: .radialGradient(
                            Gradient(colors: [variant.phosphor.glow.opacity(0.28), .clear]),
                            center: center, startRadius: 30, endRadius: 280))
                    for y in stride(from: CGFloat(0), to: size.height, by: 4) {
                        context.fill(
                            Path(CGRect(x: 0, y: y + 2, width: size.width, height: 2)),
                            with: .color(.black.opacity(0.32)))
                    }
                    context.fill(
                        bounds,
                        with: .radialGradient(
                            Gradient(colors: [.clear, .black.opacity(0.55)]),
                            center: center, startRadius: size.width * 0.35,
                            endRadius: hypot(size.width, size.height) * 0.6))
                }
                .ignoresSafeArea()
            }
    }
}

private struct StatTile: View {
    var value: Int
    var label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.title.bold()).monospacedDigit()
            Text(label).font(.callout).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.textSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
