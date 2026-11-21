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
            ("NOTICE", "Silverbox/Licenses/Silverbox-Notice.txt"),
            ("Sources/CStbVorbis/LICENSE", "Silverbox/Licenses/stb_vorbis.txt"),
            ("Sources/CXmpLite/LICENSE", "Silverbox/Licenses/libxmp-lite.txt"),
        ]
        for (source, copy) in pairs {
            let original = try String(contentsOf: Self.root.appendingPathComponent(source), encoding: .utf8)
            let bundled = try String(contentsOf: Self.root.appendingPathComponent(copy), encoding: .utf8)
            #expect(original == bundled, "\(copy) differs from \(source)")
        }
    }

    /// The font the app bundles comes with its license, as the license asks.
    @Test func bundledFontHasItsLicense() throws {
        let font = Self.root.appendingPathComponent("Silverbox/Fonts/VT323-Regular.ttf")
        #expect(FileManager.default.fileExists(atPath: font.path))
        let license = try String(
            contentsOf: Self.root.appendingPathComponent("Silverbox/Licenses/VT323.txt"), encoding: .utf8)
        #expect(license.hasPrefix("Copyright 2011, The VT323 Project Authors"))
        #expect(license.contains("SIL OPEN FONT LICENSE Version 1.1"))
        let notice = try String(contentsOf: Self.root.appendingPathComponent("NOTICE"), encoding: .utf8)
        #expect(notice.contains("Silverbox/Fonts/VT323-Regular.ttf"))
    }

    @Test func licenseIsTheGPL() throws {
        let license = try String(contentsOf: Self.root.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(
            license.hasPrefix(
                "                    GNU GENERAL PUBLIC LICENSE\n                       Version 3, 29 June 2007\n"))
        #expect(license.contains("END OF TERMS AND CONDITIONS"))
    }

    @Test func noticeKeepsTheNameAndIcons() throws {
        let notice = try String(contentsOf: Self.root.appendingPathComponent("NOTICE"), encoding: .utf8)
        #expect(notice.contains("either version 3 of the License, or (at your option) any later version"))
        #expect(notice.contains("The name \"Silverbox\" and the icon and logo artwork"))
    }
}
