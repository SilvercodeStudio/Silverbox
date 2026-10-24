import AppKit
import SwiftUI
import eXoCore

/// The look from the design prototypes, dark or light with the system or
/// the Appearance setting, and accented in the colour of the chosen app
/// icon: amber or green. Each colour has a value for each appearance.
enum Theme {
    static let window = Color(light: 0xF4F4F6, dark: 0x181A1D)
    static let sidebar = Color(light: 0xE9EAED, dark: 0x202226)
    static let panel = Color(light: 0xFAFAFB, dark: 0x1D1F23)
    static let panelRaised = Color(light: 0xFFFFFF, dark: 0x26292E)
    static let card = Color(light: 0xFFFFFF, dark: 0x24262A)
    static let field = Color(light: 0xFFFFFF, dark: 0x1A1C1F)
    static let border = Color(light: 0xDCDDE1, dark: 0x2A2D32)
    static let borderStrong = Color(light: 0xC4C6CC, dark: 0x3A3E45)
    static let textPrimary = Color(light: 0x1C1D20, dark: 0xECEDEF)
    static let textSecondary = Color(light: 0x5B5F67, dark: 0xA3A7AE)
    static let textTertiary = Color(light: 0x777C84, dark: 0x8C9199)
    /// Status tones: a thing that is ready, one that needs attention, and
    /// one that is broken. Kept apart from the amber accent so that a
    /// warning never looks like a highlight.
    static let good = Color(light: 0x237A3C, dark: 0x5BC46E)
    static let warning = Color(light: 0xB8561A, dark: 0xF08A4B)
    static let bad = Color(light: 0xC1272D, dark: 0xF2655C)
    static var accent: Color { ThemeAccent.shared.variant.accent }
    /// Text on an accent fill, such as the Play button.
    static var accentText: Color { ThemeAccent.shared.variant.accentText }
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

    /// The tint behind a game's header in the inspector and on its page.
    static func toneColor(for title: String) -> Color {
        let hue = hue(for: title)
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.isDark
                    ? NSColor(hue: hue, saturation: 0.32, brightness: 0.27, alpha: 1)
                    : NSColor(hue: hue, saturation: 0.18, brightness: 0.92, alpha: 1)
            })
    }
}

/// The icon whose colour accents the app. Views that read ``Theme/accent``
/// redraw when it changes.
@Observable
final class ThemeAccent {
    static let shared = ThemeAccent()
    var variant: AppIconVariant = .amber
}

extension AppIconVariant {
    /// A softer take on the icon's phosphor (amber #FFB000, green #33FF00),
    /// dark enough for dark text on it, and darker again on a light
    /// background so that it reads as text and outlines.
    var accentHex: (light: UInt32, dark: UInt32) {
        switch self {
        case .amber: return (0xC0820F, 0xF2B544)
        case .green: return (0x2E8B42, 0x3FA453)
        }
    }

    var accent: Color { Color(light: accentHex.light, dark: accentHex.dark) }

    var accentText: Color {
        switch self {
        case .amber: return Color(hex: 0x1B1404)
        case .green: return Color(hex: 0x06170B)
        }
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

    /// A colour that follows the window's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                NSColor(hex: appearance.isDark ? dark : light)
            })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

enum Formatters {
    static func playTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0, minutes == 0, seconds > 0 { return "\(seconds)s" }
        return "\(hours)h \(String(format: "%02d", minutes))m"
    }

    /// "3:07" for a track position or length.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
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
            let hasDay =
                Calendar.current.component(.day, from: date) != 1 || Calendar.current.component(.month, from: date) != 1
            parts.append(
                "Released " + (hasDay ? date.formatted(date: .long, time: .omitted) : String(game.releaseYear ?? 0)))
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
