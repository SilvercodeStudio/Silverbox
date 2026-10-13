import Foundation
import Testing

@testable import eXoCore

@Suite("Soundtracks")
struct SoundtrackTests {
    @Test func foobarEntryIsASoundtrackWithItsZipResolved() {
        let game = Game(
            id: "s1", title: "Dune: Spice Opera (Soundtrack)", platform: "Soundtracks",
            applicationPath: "eXo\\emulators\\audio\\foobar2000\\foobar2000.exe",
            commandLine: "\"..\\..\\..\\Soundtracks\\Dune- Spice Opera.zip\"",
            rootFolder: "eXo\\emulators\\audio\\foobar2000")
        #expect(game.launchKind == .soundtrack)
        let root = LibraryRoot(url: URL(fileURLWithPath: "/Volumes/eXoDOS"))
        #expect(
            SoundtrackLibrary.archiveURL(for: game, root: root)?.path
                == "/Volumes/eXoDOS/eXo/Soundtracks/Dune- Spice Opera.zip")
    }

    @Test func otherWindowsProgramsAreNotSoundtracks() {
        let game = Game(
            id: "w", title: "Setup", platform: "MS-DOS", applicationPath: "eXo\\util\\setup.exe",
            commandLine: "\"x.zip\"")
        #expect(game.launchKind == .windowsProgram)
    }

    @Test func trackNamesParse() {
        #expect(SoundtrackLibrary.parse(trackName: "01 Chapel Pain - The Game").number == 1)
        #expect(SoundtrackLibrary.parse(trackName: "01 Chapel Pain - The Game").title == "Chapel Pain - The Game")
        #expect(SoundtrackLibrary.parse(trackName: "07. Skeletons").title == "Skeletons")
        #expect(SoundtrackLibrary.parse(trackName: "Track 3 - Foo").number == 3)
        #expect(SoundtrackLibrary.parse(trackName: "1942 Theme").number == nil)
        #expect(SoundtrackLibrary.parse(trackName: "Opening").title == "Opening")
    }

    @Test func tracksSortByNumberAndCoverIsFound() {
        let folder = URL(fileURLWithPath: "/tmp/album")
        let album = SoundtrackLibrary.album(
            archiveURL: URL(fileURLWithPath: "/lib/eXo/Soundtracks/A.zip"), folderURL: folder,
            entries: ["10 Ten.flac", "02 Two.flac", "cover.jpg", "__MACOSX/._02 Two.flac", "01 One.flac", "notes.txt"],
            unpacked: true)
        #expect(album.tracks.map(\.title) == ["One", "Two", "Ten"])
        #expect(album.tracks.first?.url == folder.appendingPathComponent("01 One.flac"))
        #expect(album.coverURL == folder.appendingPathComponent("cover.jpg"))
        #expect(album.formats == ["FLAC"])
        #expect(album.folderURL == folder)
    }
}
