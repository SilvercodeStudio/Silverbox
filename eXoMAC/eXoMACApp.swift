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
        }
        .defaultSize(width: 1320, height: 840)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        Window("\(AppInfo.displayName) Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 620)

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("About \(AppInfo.displayName)", id: "about") {
            AboutView()
                .environment(model)
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
