import SwiftUI
import WebKit
import eXoCore

/// One help page, read from the bundled Markdown files.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let markdown: String
}

enum HelpLibrary {
    static func topics() -> [HelpTopic] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? []
        return
            urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let fallback = url.deletingPathExtension().lastPathComponent
                    .drop(while: { $0.isNumber || $0 == " " })
                return HelpTopic(
                    id: url.lastPathComponent, title: MarkdownHTML.title(of: markdown) ?? String(fallback),
                    markdown: markdown)
            }
    }
}

/// Lets other windows ask the Help window to show a page.
@Observable
final class HelpState {
    static let shared = HelpState()

    struct Request: Equatable {
        let id = UUID()
        /// The numeric prefix of the page file, for example "03".
        let topicPrefix: String
    }

    private(set) var request: Request?

    func show(topicPrefix: String) {
        request = Request(topicPrefix: topicPrefix)
    }
}

struct HelpView: View {
    @State private var topics = HelpLibrary.topics()
    @State private var selection: String?
    private let helpState = HelpState.shared

    var body: some View {
        NavigationSplitView {
            List(topics, selection: $selection) { topic in
                Text(topic.title).tag(topic.id)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let topic = topics.first(where: { $0.id == selection }) ?? topics.first {
                HelpWebView(html: MarkdownHTML.page(body: MarkdownHTML.render(topic.markdown)))
            } else {
                Text("No help pages are bundled.").foregroundStyle(.secondary)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 700, minHeight: 480)
        .onAppear { select(helpState.request) }
        .onChange(of: helpState.request) { _, request in select(request) }
    }

    private func select(_ request: HelpState.Request?) {
        if let request, let topic = topics.first(where: { $0.id.hasPrefix(request.topicPrefix) }) {
            selection = topic.id
        } else if selection == nil {
            selection = topics.first?.id
        }
    }
}

struct HelpWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

/// The About panel with the product name, version and credits.
enum AboutPanel {
    static let productName = AppInfo.displayName
    static let projectURL = URL(string: "https://www.retro-exo.com")!

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

/// The About window: the app icon beside the credits, with the eXoDOS cover
/// under the text.
struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: model.settings.appIcon.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 170)
            VStack(alignment: .leading, spacing: 10) {
                Text(AboutPanel.productName)
                    .font(.title2.weight(.semibold))
                Text(AboutPanel.version)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text("A Mac front-end for the eXoDOS and eXoWin9x game preservation collections.")
                    .padding(.top, 4)
                Text("Emulation by DOSBox Staging, DOSBox-X, RetroArch, Dolphin, MAME and Mednafen.")
                HStack(alignment: .center, spacing: 12) {
                    Image("eXoDOSCover")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("eXoDOS and eXoWin9x are projects of the eXo team.")
                        Link(AboutPanel.projectURL.absoluteString, destination: AboutPanel.projectURL)
                        Text("eXoDOS 6: Forever Voyaging")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 4)
                Text(
                    "Includes stb_vorbis by Sean Barrett and libxmp-lite by Claudio Matsuoka and Hipolito Carraro Jr, both MIT licensed."
                )
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 4)
            }
            .font(.callout)
            .frame(width: 330, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .padding(.top, 12)
        .background(Theme.window)
        .preferredColorScheme(.dark)
    }
}
