import eXoCore
import SwiftUI

/// The dark, amber-accented look from the design prototypes.
enum Theme {
    static let window = Color(hex: 0x181A1D)
    static let sidebar = Color(hex: 0x202226)
    static let panel = Color(hex: 0x1D1F23)
    static let panelRaised = Color(hex: 0x26292E)
    static let card = Color(hex: 0x24262A)
    static let field = Color(hex: 0x1A1C1F)
    static let border = Color(hex: 0x2A2D32)
    static let borderStrong = Color(hex: 0x3A3E45)
    static let textPrimary = Color(hex: 0xECEDEF)
    static let textSecondary = Color(hex: 0xA3A7AE)
    static let textTertiary = Color(hex: 0x8C9199)
    static let accent = Color(hex: 0xF2B544)
    static let accentText = Color(hex: 0x1B1404)
    static let mono = Font.system(size: 11, design: .monospaced)

    /// A stable hue for a title, used for placeholder tiles and header tints.
    static func hue(for title: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in title.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Double(hash % 360) / 360
    }

    static func tileColor(for title: String) -> Color {
        Color(hue: hue(for: title), saturation: 0.38, brightness: 0.42)
    }

    static func toneColor(for title: String) -> Color {
        Color(hue: hue(for: title), saturation: 0.32, brightness: 0.27)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Formatters {
    static func playTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0, minutes == 0, seconds > 0 { return "\(seconds)s" }
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    static func elapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func releaseLine(_ game: Game) -> String {
        var parts: [String] = []
        if let date = game.releaseDate {
            let hasDay = Calendar.current.component(.day, from: date) != 1 || Calendar.current.component(.month, from: date) != 1
            parts.append("Released " + (hasDay ? date.formatted(date: .long, time: .omitted) : String(game.releaseYear ?? 0)))
        }
        if let developer = game.developer { parts.append("by \(developer)") }
        return parts.joined(separator: " ")
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

extension LibraryNode {
    /// `nil` for leaves, as `OutlineGroup` expects.
    var outlineChildren: [LibraryNode]? {
        children.isEmpty ? nil : children
    }

    var systemImage: String {
        switch ref {
        case .category: return "folder"
        case .playlist: return "list.bullet"
        case .platform(let name):
            let lowered = name.lowercased()
            if lowered.contains("book") || lowered.contains("magazine") || lowered.contains("catalog") { return "book" }
            if lowered.contains("soundtrack") || lowered.contains("audio") { return "music.note" }
            return "desktopcomputer"
        }
    }
}

extension Game {
    /// The part of the title before a colon, for placeholder tiles.
    var shortTitle: String {
        if let colon = title.firstIndex(of: ":") { return String(title[..<colon]) }
        return title
    }

    /// The part of the title after a colon, if any.
    var subtitle: String? {
        guard let colon = title.firstIndex(of: ":") else { return nil }
        let rest = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }
}
