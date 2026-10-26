import Foundation
import Testing

@testable import SilverboxCore

@Suite("Videos")
struct VideoTests {
    private let folder = URL(fileURLWithPath: "/lib/eXo/Videos/Show")

    @Test func videoLaunchersAreVideos() {
        let game = Game(
            id: "v", title: "Get Lamp", platform: "MS-DOS Videos",
            applicationPath: "eXo\\Videos\\Get Lamp (2007)\\run.bat")
        #expect(game.launchKind == .video)
        let elsewhere = Game(
            id: "w", title: "Setup", platform: "MS-DOS", applicationPath: "eXo\\util\\setup.bat")
        #expect(elsewhere.launchKind == .windowsProgram)
    }

    @Test func singleVideoIsNamedAfterTheBatchFile() {
        let text = """
            echo off\r
            ..\\..\\util\\setconsole.exe /minimize\r
            set filename=%~n0\r
            ..\\..\\util\\VLC\\vlc.exe "%filename%.mp4"\r
            """
        let items = VideoLibrary.items(
            batchText: text, batchURL: folder.appendingPathComponent("Sierra 1989 Video Catalog.bat"))
        #expect(items.map(\.url) == [folder.appendingPathComponent("Sierra 1989 Video Catalog.mp4")])
        #expect(items.map(\.title) == ["Sierra 1989 Video Catalog"])
    }

    @Test func menuOfLabelsListsDiscsInMenuOrder() {
        let text = """
            set var=%cd%
            echo off
            cls
            echo Press 1 to Play Disc 1
            echo Press 2 to Play Disc 2
            choice /C 12 /M "Please Choose:"

            if errorlevel = 2 goto disc2
            if errorlevel = 1 goto disc1

            :disc1
            cd ..\\..\\..
            .\\exo\\util\\VLC\\vlc.exe --width="1920" "%var%\\GET LAMP Disc 1.ISO"
            goto quit

            :disc2
            cd ..\\..\\..
            .\\exo\\util\\VLC\\vlc.exe --width="1920" "%var%\\GET LAMP Disc 2.ISO"
            goto quit

            :quit
            """
        let items = VideoLibrary.items(batchText: text, batchURL: folder.appendingPathComponent("run.bat"))
        #expect(items.map(\.title) == ["Disc 1", "Disc 2"])
        #expect(items.first?.url == folder.appendingPathComponent("GET LAMP Disc 1.ISO"))
        #expect(items.first?.isDiscImage == true)
    }

    @Test func pagedMenuWithVariablesSkipsPageLinks() {
        let text = """
            set var=%cd%
            :main
            cls
            echo Press 1 for S01E21: Computer Games (1984)
            echo Press 2 for S02E03: Computer   Games (1985)
            echo Press N to go to the Next Page
            choice /C 12N /N /M "Please Choose:"

            if errorlevel = 3 goto main2
            if errorlevel = 2 (
                        set title=S02E03
            \tgoto play
            )
            if errorlevel = 1 (
                        set title=S01E21
            \tgoto play
            )

            :main2
            cls
            echo Press 1 for S08E21: CD-ROM Software (1991)
            echo Press P to go to the Previous Page
            choice /C 1P /N /M "Please Choose:"

            if errorlevel = 2 goto main
            if errorlevel = 1 (
                        set title=S08E21
            \tgoto play
            )

            :play
            cd ..\\..\\..
            .\\exo\\util\\VLC\\vlc.exe --width="1920" "%var%\\%title%.mp4"
            goto quit

            :quit
            """
        let items = VideoLibrary.items(batchText: text, batchURL: folder.appendingPathComponent("run.bat"))
        #expect(
            items.map(\.title) == [
                "S01E21: Computer Games (1984)", "S02E03: Computer Games (1985)", "S08E21: CD-ROM Software (1991)",
            ])
        #expect(items.map(\.url.lastPathComponent) == ["S01E21.mp4", "S02E03.mp4", "S08E21.mp4"])
    }

    @Test func nestedMenusAndGoBackItems() {
        let text = """
            set var=%cd%
            :main
            cls
            echo Press 1 to goto Season 1
            choice /C 1 /M "Please Choose:"
            if errorlevel = 1 goto s1

            :s1
            cls
            echo Press 1 for Episode 09: Will Wright
            echo Press 2 to Go Back
            choice /C 12 /M "Please Choose:"
            if errorlevel = 2 goto main
            if errorlevel = 1 goto ep09

            :ep09
            cd ..\\..\\..
            .\\ThirdParty\\VLC\\x64\\vlc.exe --width="1920" "%var%\\G4 Icons Episode 09 Will Wright.mp4"
            goto quit
            """
        let items = VideoLibrary.items(batchText: text, batchURL: folder.appendingPathComponent("run.bat"))
        #expect(items.map(\.title) == ["Episode 09: Will Wright"])
        #expect(items.first?.url == folder.appendingPathComponent("G4 Icons Episode 09 Will Wright.mp4"))
    }

    /// Every video entry of a mounted eXoDOS install finds at least one file.
    @Test(.enabled(if: RealLibrary.isAvailable)) func realVideoEntriesFindTheirFiles() throws {
        let snapshot = try LibraryLoader(root: RealLibrary.root).load()
        let videos = snapshot.games.filter { $0.launchKind == .video }
        #expect(videos.count > 10)
        for game in videos.sorted(by: { $0.title < $1.title }) {
            let items = VideoLibrary.items(for: game, root: RealLibrary.root)
            print("\(game.title): \(items.map(\.title).joined(separator: " | "))")
            #expect(!items.isEmpty, Comment(rawValue: game.title))
        }
    }
}
