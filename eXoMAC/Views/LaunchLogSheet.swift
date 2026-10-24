import AppKit
import SwiftUI
import eXoCore

/// The emulator's output for one launch, with the command that started it,
/// as a report a user can copy into a bug report.
struct LaunchLogSheet: View {
    let session: GameSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var log = ""
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BoxArtView(game: session.game, width: 44, maxPixelSize: 128)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.game.title).font(.headline)
                    Text(
                        "\(session.launch.emulator.kind.displayName) · started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    ChipRow {
                        if session.isRunning {
                            Chip(text: "Running", tone: .good, isWorking: true)
                        } else if session.exitStatus == 0 {
                            Chip(text: "Exited normally", tone: .good, systemImage: "checkmark.circle")
                        } else {
                            Chip(
                                text: "Exit code \(session.exitStatus)", tone: .bad,
                                systemImage: "exclamationmark.triangle")
                        }
                        if let ended = session.endedAt {
                            Chip(
                                text: "Ran \(Formatters.clock(ended.timeIntervalSince(session.startedAt)))",
                                systemImage: "clock")
                        }
                        if !session.launch.notes.isEmpty {
                            Chip(
                                text: session.launch.notes.count == 1
                                    ? "1 note" : "\(session.launch.notes.count) notes",
                                systemImage: "text.alignleft")
                        }
                    }
                }
            }
            Text(session.launch.commandLine)
                .font(Theme.mono)
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
            LogText(text: log.isEmpty ? "The emulator wrote nothing to its log." : log)
            HStack {
                Button("Copy Log") { copy(log, as: "Log") }
                    .disabled(log.isEmpty)
                Button("Copy as Markdown") {
                    copy(model.launchReport(for: session, log: log).markdown, as: "Report")
                }
                .help("The emulator, command line, config, notes and the end of the log, for a bug report")
                if let url = session.logURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                if let copied {
                    Text("\(copied) copied").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 720, height: 520)
        .task(id: session.id) { log = await Task.detached { AppModel.logText(of: session) }.value }
    }

    private func copy(_ text: String, as label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = label
    }
}

/// A monospaced, selectable log that starts scrolled to its newest line.
struct LogText: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text)
                    .font(Theme.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                Color.clear.frame(height: 1).id("end")
            }
            .background(Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
            .onChange(of: text, initial: true) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}
