import SwiftUI
import WebKit
import SilverboxCore

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
                HelpWebView(
                    html: MarkdownHTML.page(
                        body: MarkdownHTML.render(topic.markdown), accent: ThemeAccent.shared.variant.accentHex))
            } else {
                Text("No help pages are bundled.").foregroundStyle(.secondary)
            }
        }
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
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
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
