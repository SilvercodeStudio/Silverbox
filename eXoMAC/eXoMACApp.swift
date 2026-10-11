//
//  eXoMACApp.swift
//  eXoMAC
//
//  An emulation front-end for the eXoDOS and eXoWin9x collections on the Mac.
//

import SwiftUI

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
    }
}

/// Names shown to the user. Internal names stay `eXoMAC`.
enum AppInfo {
    static let displayName = "eXo Client"
    static let fullName = "eXo Client for Mac"
}
