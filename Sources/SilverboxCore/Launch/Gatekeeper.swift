import Foundation

#if canImport(Darwin)
    import Darwin
#endif

/// Whether macOS will refuse to start an emulator. An app from a download
/// carries a quarantine mark. Until the user has opened or allowed the app,
/// macOS checks it at its first start, and stops one that Apple has not
/// notarized (the DOSBox-X download, for one) with a warning that offers to
/// move it to the Trash. The user then allows it in System Settings ›
/// Privacy & Security, with Open Anyway. Nothing here changes the mark:
/// allowing an app is the user's decision.
nonisolated public enum Gatekeeper {
    nonisolated public enum Verdict: Sendable, Equatable {
        /// No mark, or the user has allowed the app, or Apple has notarized it.
        case allowed
        /// macOS will stop the app until the user allows it.
        case blocked
        /// Marked and not allowed yet; `isBlocked(app:)` has not asked macOS about it.
        case unknown
    }

    static let quarantineAttribute = "com.apple.quarantine"
    /// The flag, in the mark's first field ("01c1;…"), that says the user
    /// opened or allowed the app.
    static let approvedFlag: UInt32 = 0x0040

    /// True for the mark of a download that the user has not allowed yet:
    /// "0181;6acedaa5;Chrome;…", but not "01c1;…". A mark that cannot be
    /// read as one is not taken for a reason to warn.
    public static func awaitsApproval(mark: String) -> Bool {
        guard let field = mark.split(separator: ";", omittingEmptySubsequences: false).first,
            let flags = UInt32(field, radix: 16)
        else { return false }
        return flags & approvedFlag == 0
    }

    /// The app's quarantine mark, or nil when it has none (a Homebrew
    /// program, an app built here, or any file on another system).
    public static func quarantineMark(of app: URL) -> String? {
        #if canImport(Darwin)
            let size = getxattr(app.path, quarantineAttribute, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: size)
            let read = getxattr(app.path, quarantineAttribute, &bytes, size, 0, 0)
            guard read > 0 else { return nil }
            return String(decoding: bytes.prefix(read), as: UTF8.self)
        #else
            return nil
        #endif
    }

    /// The answer without asking macOS: `.allowed` and remembered answers
    /// are quick; `.unknown` means `isBlocked(app:)` has to be called, off
    /// the main thread.
    public static func quickVerdict(app: URL) -> Verdict {
        guard let mark = quarantineMark(of: app), awaitsApproval(mark: mark) else { return .allowed }
        return answers.value(for: key(app, mark)).map { $0 ? .blocked : .allowed } ?? .unknown
    }

    /// True when macOS will stop the app at its start. For a marked app that
    /// the user has not allowed, this asks macOS's own assessment (`spctl`),
    /// which reads the whole app, so the answer is kept for that mark. Call
    /// it off the main thread.
    public static func isBlocked(app: URL) -> Bool {
        guard let mark = quarantineMark(of: app), awaitsApproval(mark: mark) else { return false }
        let key = key(app, mark)
        if let known = answers.value(for: key) { return known }
        let blocked = assessmentRejects(app)
        answers.set(blocked, for: key)
        return blocked
    }

    private static func key(_ app: URL, _ mark: String) -> String { app.path + "\n" + mark }

    /// Runs `spctl --assess`, which ends with 3 for an app that Gatekeeper
    /// rejects. Any other end (accepted, assessments turned off, no spctl)
    /// is no reason to warn.
    private static func assessmentRejects(_ app: URL) -> Bool {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
            process.arguments = ["--assess", "--type", "execute", app.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return false
            }
            process.waitUntilExit()
            return process.terminationReason == .exit && process.terminationStatus == 3
        #else
            return false
        #endif
    }

    private static let answers = Answers()

    /// The assessments made so far, by app path and mark.
    private final class Answers: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Bool] = [:]

        func value(for key: String) -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        func set(_ value: Bool, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }
    }
}

nonisolated extension EmulatorInstallation {
    /// What macOS checks at the emulator's start: the app, or the program
    /// itself when it is not inside one.
    public var gatekeeperTarget: URL { appBundleURL ?? executableURL }
}
