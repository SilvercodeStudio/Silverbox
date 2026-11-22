import Foundation

/// A path as a window shows it. For the site's screenshots, a debug build takes
/// `-redactPaths "planders=USERNAME|Tim Apple=STORAGE"`, which replaces those words in the
/// paths the windows show, and nowhere else: the files are still found where they are.
nonisolated func shownPath(_ path: String) -> String {
    #if DEBUG
        PathRedaction.replacements.reduce(path) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    #else
        path
    #endif
}

#if DEBUG
    nonisolated private enum PathRedaction {
        static let replacements: [(String, String)] =
            (UserDefaults.standard.string(forKey: "redactPaths") ?? "").split(separator: "|").compactMap { pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 && !parts[0].isEmpty ? (parts[0], parts[1]) : nil
            }
    }
#endif
