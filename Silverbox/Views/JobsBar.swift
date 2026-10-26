import SwiftUI
import SilverboxCore

/// The bottom bar for background jobs: one row per installation, with its
/// progress, the step under way, the time it has taken and a Cancel
/// button; a finished or failed one stays a moment with its result.
struct JobsBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(model.installRuns) { run in
            JobRow(run: run)
        }
    }
}

private struct JobRow: View {
    let run: InstallRun
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            indicator
                .frame(width: 140, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(.caption)
                    .foregroundStyle(tone)
                Text(run.game.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 160, maxWidth: 320, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(run.phase == .running ? Theme.textSecondary : tone)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if run.isRunning {
                TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                    Text(Formatters.elapsed(context.date.timeIntervalSince(run.startedAt)))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }
                Button("Cancel") { run.cancel() }
                    .help(
                        run.isDownloading
                            ? "Stop the download; it resumes where it stopped when you install the game again"
                            : "Stop unpacking; the game folder is removed")
            } else {
                Button("Dismiss") { model.dismissInstallRun(run) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.panelRaised)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var indicator: some View {
        switch run.phase {
        case .running:
            if let fraction = run.fraction {
                ProgressView(value: fraction).tint(Theme.accent)
            } else {
                ProgressView().controlSize(.small)
            }
        case .finished:
            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good).font(.caption)
        case .cancelled:
            Label("Stopped", systemImage: "minus.circle").foregroundStyle(Theme.textSecondary).font(.caption)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(Theme.bad).font(.caption)
        }
    }

    private var headline: String {
        switch run.phase {
        case .running: "Installing"
        case .finished: "Installed"
        case .cancelled: "Installation stopped"
        case .failed: "Installation failed"
        }
    }

    private var detail: String {
        switch run.phase {
        case .running: [run.stage, run.detail].compactMap { $0 }.joined(separator: " · ")
        case .finished: "Ready to play"
        case .cancelled: run.isDownloading ? "The download resumes on the next try" : "Nothing was kept"
        case .failed(let message): message
        }
    }

    private var tone: Color {
        switch run.phase {
        case .running: Theme.accent
        case .finished: Theme.good
        case .cancelled: Theme.textSecondary
        case .failed: Theme.bad
        }
    }
}
