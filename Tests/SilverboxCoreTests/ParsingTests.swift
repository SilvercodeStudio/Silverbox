import Foundation
import Testing

@testable import SilverboxCore

@Suite("LaunchBox dates")
struct LaunchBoxDateTests {
    @Test func parsesFractionalSecondsAndZone() throws {
        let date = try #require(LaunchBoxDate.parse("2017-12-11T09:09:53.788151-06:00"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -6 * 3600)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(parts.year == 2017 && parts.month == 12 && parts.day == 11)
        #expect(parts.hour == 9 && parts.minute == 9 && parts.second == 53)
    }

    @Test func parsesPlainZonedDate() {
        #expect(LaunchBoxDate.parse("1988-10-05T02:00:00-05:00") != nil)
    }

    @Test func rejectsDotNetMinimum() {
        #expect(LaunchBoxDate.parse("0001-01-01T00:00:00") == nil)
        #expect(LaunchBoxDate.parse("") == nil)
    }

    @Test func roundTrips() throws {
        let date = try #require(LaunchBoxDate.parse("1988-10-05T02:00:00-05:00"))
        let again = try #require(LaunchBoxDate.parse(LaunchBoxDate.format(date)))
        #expect(abs(again.timeIntervalSince(date)) < 1)
    }
}

@Suite("LaunchBox XML")
struct LaunchBoxXMLTests {
    @Test func streamsGameRecords() throws {
        let url = FixtureLibrary.root.platformFile(named: "MS-DOS")
        var elements: [String] = []
        try LaunchBoxXMLParser.parse(url: url) { elements.append($0.element) }
        #expect(elements == ["Game", "Game", "Game", "AdditionalApplication", "AlternateName", "AlternateName"])
    }

    @Test func mapsGameFields() throws {
        let records = try LaunchBoxXMLParser.parseAll(url: FixtureLibrary.root.platformFile(named: "MS-DOS"))
        let game = try #require(Game(record: records[0]))
        #expect(game.launchBoxID == FixtureLibrary.ultimaID)
        #expect(game.title == "Ultima V: Warriors of Destiny")
        #expect(game.sortTitle == "Ultima 5")
        #expect(game.developer == "ORIGIN Systems, Inc.")
        #expect(game.favorite == true)
        #expect(game.releaseYear == 1988)
        #expect(game.genres == ["Role-Playing"])
        #expect(game.series == ["Playlist: Roland MT-32", "Playlist: Sound Canvas", "Theme: Fantasy", "Ultima series"])
        #expect(game.playlistTags == ["Roland MT-32", "Sound Canvas"])
        #expect(game.themeTags == ["Fantasy"])
        #expect(game.seriesNames == ["Ultima series"])
        #expect(game.notes?.contains("\n\nIn Ultima V") == true)
        #expect(game.launcherBaseName == "Ultima V - Warriors of Destiny (1988)")
        #expect(game.gameFolderName == "ultima5")
        #expect(game.communityStarRating == 4.5)
        #expect(game.communityStarRatingVotes == 10)
        #expect(game.missingMedia.contains(.video))
        #expect(!game.missingMedia.contains(.boxFront))
        #expect(game.isDOSGame)
        #expect(game.maxPlayers == 1)
    }

    @Test func mapsAlternateNamesAndApps() throws {
        let records = try LaunchBoxXMLParser.parseAll(url: FixtureLibrary.root.platformFile(named: "MS-DOS"))
        let app = try #require(AdditionalApplication(record: records[3]))
        #expect(app.name == "eXoDOS Updater")
        #expect(app.gameID == FixtureLibrary.ultimaID)
        let alt = try #require(AlternateName(record: records[5]))
        #expect(alt.name == "Ultima Quintus")
        #expect(alt.region == "Japan")
    }

    @Test func parsesInMemoryXML() throws {
        let xml =
            "<LaunchBox><Parent><PlatformName>A &amp; B</PlatformName><ParentPlatformCategoryName>C</ParentPlatformCategoryName></Parent></LaunchBox>"
        var links: [ParentLink] = []
        try LaunchBoxXMLParser.parse(data: Data(xml.utf8)) {
            if let link = ParentLink(record: $0) { links.append(link) }
        }
        #expect(links == [ParentLink(child: .platform("A & B"), parent: .category("C"))])
    }
}

@Suite("Windows paths")
struct WindowsPathTests {
    @Test func splitsAndResolves() {
        #expect(WindowsPath.components(of: "eXo\\eXoDOS\\!dos\\ultima5") == ["eXo", "eXoDOS", "!dos", "ultima5"])
        #expect(
            WindowsPath.baseName(of: "eXo\\eXoDOS\\!dos\\ultima5\\Ultima V - Warriors of Destiny (1988).bat")
                == "Ultima V - Warriors of Destiny (1988)")
        #expect(WindowsPath.fileExtension(of: "a\\b.PDF") == "PDF")
        #expect(WindowsPath.isAbsolute("C:\\Games"))
        #expect(!WindowsPath.isAbsolute(".\\mt32"))
        let base = URL(fileURLWithPath: "/lib/eXo", isDirectory: true)
        #expect(WindowsPath.resolve("..\\Images\\x.png", against: base).path == "/lib/Images/x.png")
        #expect(WindowsPath.resolve(".\\eXoDOS\\", against: base).path == "/lib/eXo/eXoDOS")
    }

    @Test func libraryRootResolvesRelativePaths() {
        let root = LibraryRoot(url: URL(fileURLWithPath: "/Volumes/eXoDOS"))
        #expect(
            root.url(forWindowsRelativePath: "Manuals\\MS-DOS\\Foo.pdf").path
                == "/Volumes/eXoDOS/Manuals/MS-DOS/Foo.pdf")
        #expect(root.gameConfigsDirectory.path == "/Volumes/eXoDOS/eXo/eXoDOS/!dos")
        #expect(
            root.platformFile(named: "MS-DOS Magazines & Newsletters").lastPathComponent
                == "MS-DOS Magazines & Newsletters.xml")
    }
}
