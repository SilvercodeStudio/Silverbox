import Foundation
import Testing

/// The repository's own files: the license the app shows must be the license it ships under.
@Suite("Project files")
struct ProjectFilesTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func bundledLicensesMatchTheirSources() throws {
        let pairs = [
            ("LICENSE", "Silverbox/Licenses/Silverbox.txt"),
            ("Sources/CStbVorbis/LICENSE", "Silverbox/Licenses/stb_vorbis.txt"),
            ("Sources/CXmpLite/LICENSE", "Silverbox/Licenses/libxmp-lite.txt"),
        ]
        for (source, copy) in pairs {
            let original = try String(contentsOf: Self.root.appendingPathComponent(source), encoding: .utf8)
            let bundled = try String(contentsOf: Self.root.appendingPathComponent(copy), encoding: .utf8)
            #expect(original == bundled, "\(copy) differs from \(source)")
        }
    }

    @Test func licenseKeepsTheNameAndIcons() throws {
        let license = try String(contentsOf: Self.root.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(license.contains("Permission is hereby granted, free of charge"))
        #expect(license.contains("The name \"Silverbox\" and the icon and logo artwork"))
    }
}
