import Foundation

/// Helpers for the Windows-style relative paths LaunchBox stores, such as
/// `eXo\eXoDOS\!dos\ultima5\Ultima V - Warriors of Destiny (1988).bat`.
nonisolated public enum WindowsPath {
    /// Splits on both separators and drops empty and `.` components.
    public static func components(of path: String) -> [String] {
        path.split(whereSeparator: { $0 == "\\" || $0 == "/" })
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
    }

    /// Converts separators to `/` without resolving `..`.
    public static func posix(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    public static func lastComponent(of path: String) -> String {
        components(of: path).last ?? ""
    }

    /// The last component without its extension.
    public static func baseName(of path: String) -> String {
        let name = lastComponent(of: path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    public static func fileExtension(of path: String) -> String? {
        let name = lastComponent(of: path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...]
        return ext.isEmpty ? nil : String(ext)
    }

    /// True for `C:\…`, `\\server\…` or `/…`.
    public static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("\\\\") { return true }
        let scalars = Array(path.unicodeScalars)
        return scalars.count >= 2 && scalars[1] == ":" && CharacterSet.letters.contains(scalars[0])
    }

    /// Resolves a Windows-relative path against `base`, honouring `..`.
    public static func resolve(_ path: String, against base: URL) -> URL {
        var url = base
        for component in components(of: path) {
            if component == ".." {
                url = url.deletingLastPathComponent()
            } else {
                url = url.appendingPathComponent(component)
            }
        }
        return url.standardizedFileURL
    }
}
