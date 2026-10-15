//
//  eXoMACApp.swift
//  eXoMAC
//
//  An emulation front-end for the eXoDOS and eXoWin9x collections on the Mac.
//

import SwiftUI
import eXoCore

@main
struct eXoMACApp: App {
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
    }
}

/// Names shown to the user. Internal names stay `eXoMAC`.
enum AppInfo {
    static let displayName = "Autoexec.Mac"
}
