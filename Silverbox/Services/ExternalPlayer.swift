import AppKit
import UniformTypeIdentifiers

/// An app that can open a kind of media file, for "Open in …", "Open With"
/// and the video player setting.
struct ExternalPlayer: Identifiable, Hashable {
    let name: String
    let url: URL
    /// True for the app macOS opens the file type with.
    let isDefault: Bool
    var id: URL { url }

    init(url: URL, isDefault: Bool = false) {
        self.url = url
        self.isDefault = isDefault
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    /// The app macOS opens the file type with.
    static func systemDefault(for type: UTType) -> ExternalPlayer? {
        NSWorkspace.shared.urlForApplication(toOpen: type).map { ExternalPlayer(url: $0, isDefault: true) }
    }

    /// Every app registered for the file type, the default first, then by name.
    static func all(for type: UTType) -> [ExternalPlayer] {
        let preferred = NSWorkspace.shared.urlForApplication(toOpen: type)
        return NSWorkspace.shared.urlsForApplications(toOpen: type)
            .map { ExternalPlayer(url: $0, isDefault: $0 == preferred) }
            .sorted { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// "Other…": lets the user pick any app in an open panel.
    static func choose(message: String, prompt: String = "Open") -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = prompt
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
