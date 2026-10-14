import Foundation
import eXoCore

/// A small Markdown-to-HTML converter for the help pages: headings,
/// paragraphs, bullet and numbered lists, pipe tables, fenced code, inline
/// code, bold, italics and links.
nonisolated enum MarkdownHTML {
    static func render(_ markdown: String) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var listKind: String?
        var tableLines: [String] = []
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph = []
        }
        func closeList() {
            if let kind = listKind { html.append("</\(kind)>") }
            listKind = nil
        }
        // A pipe table needs a header row and a `|---|---|` row; anything
        // else that starts with a pipe is rendered as a paragraph.
        func flushTable() {
            guard !tableLines.isEmpty else { return }
            let rows = tableLines.map(cells)
            if rows.count >= 2, rows[1].allSatisfy(isSeparatorCell) {
                html.append("<table><thead><tr>" + rows[0].map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead>")
                html.append("<tbody>")
                for row in rows.dropFirst(2) {
                    html.append("<tr>" + row.map { "<td>\(inline($0))</td>" }.joined() + "</tr>")
                }
                html.append("</tbody></table>")
            } else {
                html.append("<p>\(inline(tableLines.joined(separator: " ")))</p>")
            }
            tableLines = []
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushParagraph()
                flushTable()
                closeList()
                html.append(inCode ? "</code></pre>" : "<pre><code>")
                inCode.toggle()
                continue
            }
            if inCode {
                html.append(escape(rawLine))
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph()
                closeList()
                tableLines.append(line)
                continue
            }
            flushTable()
            if line.isEmpty {
                flushParagraph()
                closeList()
                continue
            }
            if let heading = headingLevel(line) {
                flushParagraph()
                closeList()
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                html.append("<h\(heading)>\(inline(text))</h\(heading)>")
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                if listKind != "ul" {
                    closeList()
                    listKind = "ul"
                    html.append("<ul>")
                }
                html.append("<li>\(inline(String(line.dropFirst(2))))</li>")
                continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " "
            {
                flushParagraph()
                if listKind != "ol" {
                    closeList()
                    listKind = "ol"
                    html.append("<ol>")
                }
                html.append("<li>\(inline(String(line[line.index(dot, offsetBy: 2)...])))</li>")
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        flushTable()
        closeList()
        if inCode { html.append("</code></pre>") }
        return html.joined(separator: "\n")
    }

    /// The first level-one heading, used as the page title.
    static func title(of markdown: String) -> String? {
        for line in markdown.components(separatedBy: "\n") where line.hasPrefix("# ") {
            return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func cells(_ line: String) -> [String] {
        var text = Substring(line)
        if text.hasPrefix("|") { text = text.dropFirst() }
        if text.hasSuffix("|") { text = text.dropLast() }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        cell.contains("-") && cell.allSatisfy { $0 == "-" || $0 == ":" }
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 4, line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func inline(_ text: String) -> String {
        var out = escape(text)
        out = replace(out, pattern: #"`([^`]+)`"#, with: "<code>$1</code>")
        out = replace(out, pattern: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>")
        out = replace(out, pattern: #"(?<![\w*])\*([^*]+)\*(?![\w*])"#, with: "<em>$1</em>")
        out = replace(out, pattern: #"\[([^\]]+)\]\(([^)\s]+)\)"#, with: "<a href=\"$2\">$1</a>")
        out = replace(out, pattern: #"(?<![\"=>])(https?://[^\s<)]+)"#, with: "<a href=\"$1\">$1</a>")
        return out
    }

    private static func replace(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Wraps rendered content in a page that matches the app's dark theme.
    static func page(body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        :root { color-scheme: dark; }
        body { margin: 0; padding: 28px 36px 48px; background: #181A1D; color: #ECEDEF;
               font: 14px/1.55 -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif; max-width: 72ch; }
        h1 { font-size: 24px; margin: 0 0 16px; letter-spacing: -0.01em; }
        h2 { font-size: 17px; margin: 28px 0 8px; }
        h3 { font-size: 14px; margin: 20px 0 6px; color: #D9DBDF; }
        p, li { color: #C9CCD1; }
        a { color: #F2B544; text-decoration: none; } a:hover { text-decoration: underline; }
        code { font: 12px "SF Mono", Menlo, monospace; background: #26292E; padding: 1px 5px; border-radius: 4px; color: #ECEDEF; }
        pre { background: #1D1F23; border: 1px solid #2A2D32; border-radius: 8px; padding: 12px 14px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        ul, ol { padding-left: 22px; } li { margin: 4px 0; }
        table { border-collapse: collapse; margin: 8px 0 18px; width: 100%; }
        th, td { text-align: left; vertical-align: top; padding: 6px 10px 6px 0; border-bottom: 1px solid #2A2D32; color: #C9CCD1; }
        th { color: #ECEDEF; font-weight: 600; border-bottom-color: #3A3E45; }
        td:first-child { white-space: nowrap; color: #ECEDEF; padding-right: 18px; }
        strong { color: #ECEDEF; }
        </style></head><body>\(body)</body></html>
        """
    }
}
