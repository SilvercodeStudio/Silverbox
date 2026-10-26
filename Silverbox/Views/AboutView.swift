import SwiftUI
import SilverboxCore

/// The About panel's facts, shared with the menus and the acknowledgments.
enum AboutPanel {
    static let productName = AppInfo.displayName
    static let projectURL = URL(string: "https://www.retro-exo.com")!

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    /// "© 2026 Preston Landers": the Info.plist copyright without its license
    /// note, which the License button covers.
    static var copyright: String {
        let full = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
        return full.replacingOccurrences(of: ". MIT License.", with: "")
    }
}

/// The About window, laid out like Silverside's: the icon on a CRT band, the
/// accent under it, the name and version, what the library holds, the eXo
/// credit with the eXoDOS cover, and the buttons.
struct AboutView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAcknowledgments = false
    @State private var showingLicense = false

    var body: some View {
        VStack(spacing: 0) {
            CRTHero(icon: model.settings.appIcon.image)
            Theme.accent.frame(height: 3)
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(AboutPanel.productName).font(.system(size: 34, weight: .bold))
                    Text(AboutPanel.version).font(.title3).foregroundStyle(Theme.textSecondary)
                }
                Text("Browse and play the eXo collections on your Mac.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                stats
                eXoCredit
                Text("Emulation by DOSBox Staging, DOSBox-X, 86Box, ScummVM, Spatterlight and RetroArch.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Acknowledgments…") { showingAcknowledgments = true }
                    Button("License…") { showingLicense = true }
                    Button("Website") { NSWorkspace.shared.open(AppInfo.websiteURL) }
                }
                .controlSize(.large)
                .padding(.top, 6)
                Text(AboutPanel.copyright).font(.callout).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 22)
        }
        .frame(width: 460)
        .background(Theme.window)
        .sheet(isPresented: $showingAcknowledgments) { AcknowledgmentsSheet() }
        .sheet(isPresented: $showingLicense) { LicenseSheet() }
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
                    destination: AboutPanel.projectURL)
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
/// the website's band, with scanlines, a glow in the accent colour behind the
/// icon and a darker edge. It stays dark in the light appearance, as
/// Silverside's hero does.
struct CRTHero: View {
    let icon: NSImage
    var height: CGFloat = 232
    var iconSize: CGFloat = 190

    var body: some View {
        Image(nsImage: icon)
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
                    context.fill(bounds, with: .color(Color(hex: 0x14100B)))
                    context.fill(
                        bounds,
                        with: .radialGradient(
                            Gradient(colors: [Theme.accent.opacity(0.28), .clear]),
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
