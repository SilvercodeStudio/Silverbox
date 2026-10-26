//
//  SilverboxApp.swift
//  Silverbox
//
//  An emulation front-end for the eXoDOS and eXoWin9x collections on the Mac.
//

import SwiftUI
import SilverboxCore

@main
struct SilverboxApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(AppInfo.displayName) {
            LibraryWindow()
                .environment(model)
                .tint(Theme.accent)
        }
        .defaultSize(width: 1320, height: 840)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.accent)
        }

        Window("\(AppInfo.displayName) Help", id: "help") {
            HelpView()
                .tint(Theme.accent)
        }
        .defaultSize(width: 900, height: 620)

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView()
                .environment(model)
                .tint(Theme.accent)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("About \(AppInfo.displayName)", id: "about") {
            AboutView()
                .environment(model)
                .tint(Theme.accent)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        // About is opened from the menu each time; it has no place in the Window menu or in state restoration.
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

/// Names shown to the user.
enum AppInfo {
    static let displayName = "Silverbox"
    static let websiteURL = URL(string: "https://getsilverbox.app")!
    /// "Silverbox 0.1 (2)", for reports.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(displayName) \(version) (\(build))"
    }
}
