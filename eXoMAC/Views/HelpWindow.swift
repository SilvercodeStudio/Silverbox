import SwiftUI
import WebKit

/// One help page, read from the bundled Markdown files.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let markdown: String
}

enum HelpLibrary {
    static func topics() -> [HelpTopic] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? []
        return urls
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let markdown = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let fallback = url.deletingPathExtension().lastPathComponent
                    .drop(while: { $0.isNumber || $0 == " " })
                return HelpTopic(id: url.lastPathComponent, title: MarkdownHTML.title(of: markdown) ?? String(fallback), markdown: markdown)
            }
    }
}

struct HelpView: View {
    @State private var topics = HelpLibrary.topics()
    @State private var selection: String?

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
        .onAppear { if selection == nil { selection = topics.first?.id } }
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
    static let productName = "eXo Client for Mac"
    static let projectURL = URL(string: "https://www.retro-exo.com")!

    static func show() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
        credits.append(NSAttributedString(string: "A front-end for the eXoDOS and eXoWin9x game preservation collections.\n\n", attributes: body))
        credits.append(NSAttributedString(string: "eXoDOS and eXoWin9x are projects of the eXo team.\n", attributes: body))
        credits.append(NSAttributedString(string: projectURL.absoluteString, attributes: [.font: NSFont.systemFont(ofSize: 11), .link: projectURL]))
        credits.append(NSAttributedString(string: "\n\nEmulation by DOSBox Staging and DOSBox-X.", attributes: body))
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: productName,
            .applicationVersion: version,
            .version: build,
            .credits: credits,
        ])
        NSApp.activate()
    }
}
