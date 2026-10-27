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

    /// The debug screenshot run quits by itself and must never wait for an answer.
    private var unattended: Bool { !(UserDefaults.standard.string(forKey: "screenshotPath") ?? "").isEmpty }

    /// Every alert here can be passed with "Quit Anyway", so a logout or
    /// restart is never blocked for good.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        let games = model.launcher.isRunning
        let jobs = model.hasRunningJobs
        if games || jobs, !unattended {
            let message = [
                jobs
                    ? "Installations and setup stop. You can start them again later, and a stopped download resumes."
                    : nil,
                games
                    ? "Games that are running stay open, and their files stay protected when Silverbox opens again."
                    : nil,
            ].compactMap { $0 }.joined(separator: " ")
            guard
                confirm(
                    jobs ? "Stop the running jobs and quit?" : "Quit while games are running?", message,
                    application: sender)
            else { return .terminateCancel }
        }
        guard jobs else { return saveState(of: model, application: sender) ? .terminateNow : .terminateCancel }
        // Wait for the jobs to stop, so each one removes its staging folder.
        model.cancelJobs()
        Task {
            let deadline = Date.now.addingTimeInterval(15)
            while model.hasRunningJobs, Date.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate: saveState(of: model, application: sender))
        }
        return .terminateLater
    }

    /// Saves favorites and play history. When that fails, the user can stay
    /// to try again or quit without the latest changes.
    private func saveState(of model: AppModel, application: NSApplication) -> Bool {
        guard let failure = model.flushUserState(), !unattended else { return true }
        return confirm(
            "Could not save favorites and play history",
            "\(failure) If you quit now, the latest changes are lost.", application: application)
    }

    /// True when the user chooses "Quit Anyway". Cancel is the default button.
    private func confirm(_ title: String, _ message: String, application: NSApplication) -> Bool {
        application.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
