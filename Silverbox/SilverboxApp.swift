//
//  SilverboxApp.swift
//  Silverbox
//
//  An emulation front-end for the eXoDOS and eXoWin9x collections on the Mac.
//

import AppKit
import SwiftUI
import SilverboxCore

@main
struct SilverboxApp: App {
    @NSApplicationDelegateAdaptor(SilverboxAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup(AppInfo.displayName) {
            LibraryWindow()
                .environment(model)
                .tint(Theme.accent)
                .onAppear { appDelegate.model = model }
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

final class SilverboxAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, model.launcher.isRunning {
            explain(
                "Games are still running",
                "Quit the running games before quitting Silverbox, so their files stay protected.", application: sender)
            return .terminateCancel
        }
        if let model, model.setupTask != nil || model.installRuns.contains(where: \.isRunning) {
            explain(
                "Jobs are still running",
                "Finish or cancel the active installations and setup before quitting Silverbox.", application: sender)
            return .terminateCancel
        }
        if let model, !model.flushUserState() {
            explain(
                "Could not save favorites and play history",
                model.alert?.message ?? "Try saving again before quitting.", application: sender)
            model.alert = nil
            return .terminateCancel
        }
        return .terminateNow
    }

    private func explain(_ title: String, _ message: String, application: NSApplication) {
        application.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
