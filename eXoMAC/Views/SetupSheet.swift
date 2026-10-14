import SwiftUI
import eXoCore

/// The Mac stand-in for eXo's `Setup <pack>.bat`: what the download holds,
/// the two choices that matter here, the space it needs, and progress.
struct SetupSheet: View {
    let pending: PendingSetup
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var includeAdultGames = true
    @State private var unpackGameData = false
    /// Media add-ons to leave out, by archive name.
    @State private var skippedAddOns: Set<String> = []

    private var download: EXoDownload { pending.download }
    private var running: Bool { model.setupProgress != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        pending.setUpPacks.isEmpty
                            ? "Set Up \(ListFormatter.localizedString(byJoining: download.packs.map(\.displayName)))"
                            : "Add New Packs"
                    )
                    .font(.headline)
                    Text(download.root.path)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Text(
                pending.setUpPacks.isEmpty
                    ? "This folder holds an eXo download that is not set up yet. Setup unpacks the game lists, box art, launch settings and emulator files, as eXo's setup does on Windows. Each game stays in its archive until you install it."
                    : "This folder has eXo packs that were not there at the last setup. Setup runs again for all packs and merges them, as eXo's setup does on Windows."
            )
            .fixedSize(horizontal: false, vertical: true)

            Form {
                Section("Contents") {
                    ForEach(download.packs) { pack in
                        LabeledContent(pack.displayName) {
                            Text(pending.setUpPacks.contains(pack.name) ? "Set up before" : "New")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                if !download.addOns.isEmpty {
                    Section("Media add-ons") {
                        ForEach(download.addOns) { addOn in
                            Toggle(isOn: addOnBinding(addOn)) {
                                Text(addOn.platforms.joined(separator: ", "))
                                Text(Self.bytes(addOn.size))
                            }
                        }
                        Text(
                            "Each add-on is unpacked whole. Leave one out to save its space; run the setup again to add it later."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                Section("Choices") {
                    Toggle("Include adult games", isOn: $includeAdultGames)
                    Text(
                        "eXo marks some games as adult because of nudity. When they are left out, they stay on disk but are not listed."
                    )
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    if !download.gameDataArchives.isEmpty {
                        Picker("Manuals, music and extras", selection: $unpackGameData) {
                            Text("Unpack each game's when it is installed").tag(false)
                            Text("Unpack all now (\(Self.bytes(download.gameDataSize)))").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                Section("Space") {
                    LabeledContent("Setup writes to") {
                        Text(pending.isInPlace ? "The download folder" : pending.target.path)
                            .multilineTextAlignment(.trailing)
                    }
                    if !pending.isInPlace {
                        Text(
                            "The download cannot be written, so setup writes to the local data folder. The game archives stay in the download."
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    }
                    LabeledContent("Space needed") { Text("About \(Self.bytes(neededBytes))") }
                    if let free = freeBytes {
                        LabeledContent("Space free") {
                            Text(Self.bytes(free)).foregroundStyle(free < neededBytes ? .red : Theme.textSecondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(running)

            if let progress = model.setupProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress.fraction)
                    Text([progress.stage, progress.detail].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack {
                Spacer()
                if running {
                    Button("Stop") { model.cancelSetup() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Set Up") {
                    model.startSetup(
                        pending,
                        options: EXoSetupOptions(
                            includeAdultGames: includeAdultGames, unpackGameData: unpackGameData,
                            skippedAddOns: Array(skippedAddOns)))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(running)
            }
        }
        .padding(20)
        .frame(width: 560)
        .interactiveDismissDisabled(running)
    }

    private var neededBytes: Int64 {
        let addOns = download.addOns.filter { !skippedAddOns.contains($0.archive.lastPathComponent) }
        return download.setupArchiveSize + addOns.reduce(0) { $0 + $1.size }
            + (unpackGameData ? download.gameDataSize : 0)
    }

    private func addOnBinding(_ addOn: EXoDownload.AddOn) -> Binding<Bool> {
        let name = addOn.archive.lastPathComponent
        return Binding(
            get: { !skippedAddOns.contains(name) },
            set: { keep in
                if keep { skippedAddOns.remove(name) } else { skippedAddOns.insert(name) }
            })
    }

    /// Free space on the volume setup writes to.
    private var freeBytes: Int64? {
        var url = pending.target
        while !FileManager.default.fileExists(atPath: url.path), url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
