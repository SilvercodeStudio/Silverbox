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
        WindowGroup("eXoMAC") {
            LibraryWindow()
                .environment(model)
        }
        .defaultSize(width: 1320, height: 840)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
