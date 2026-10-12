import Foundation
import Testing

@testable import eXoCore

/// The small LaunchBox-style library under `Fixtures/`.
nonisolated enum FixtureLibrary {
    static var rootURL: URL {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures folder missing from test bundle")
        }
        return url
    }

    static var root: LibraryRoot { LibraryRoot(url: rootURL) }

    static func snapshot() throws -> LibrarySnapshot {
        try LibraryLoader(root: root).load()
    }

    static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eXoMAC-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A fake emulator executable so launch planning can run without DOSBox.
    static func fakeEmulator(_ kind: EmulatorKind, in directory: URL) throws -> EmulatorInstallation {
        let url = directory.appendingPathComponent(kind.executableName)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return EmulatorInstallation(kind: kind, executableURL: url)
    }

    static let ultimaID = "80984a42-2c4e-47b3-a132-b4b439c08cfc"
    static let jeopardyID = "aaaaaaaa-0000-0000-0000-000000000002"
    static let tetrisID = "aaaaaaaa-0000-0000-0000-000000000003"
}
