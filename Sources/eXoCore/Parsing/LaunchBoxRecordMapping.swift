import Foundation

nonisolated extension Game {
    /// Builds a game from a `<Game>` record. Returns `nil` when the record has
    /// no ID or title.
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let id = r["ID"], let title = r["Title"] else { return nil }
        var missing: MissingMedia = []
        if r.bool("MissingVideo") { missing.insert(.video) }
        if r.bool("MissingBoxFrontImage") { missing.insert(.boxFront) }
        if r.bool("MissingScreenshotImage") { missing.insert(.screenshot) }
        if r.bool("MissingMarqueeImage") { missing.insert(.marquee) }
        if r.bool("MissingClearLogoImage") { missing.insert(.clearLogo) }
        if r.bool("MissingBackgroundImage") { missing.insert(.background) }
        if r.bool("MissingBox3dImage") { missing.insert(.box3D) }
        if r.bool("MissingCartImage") { missing.insert(.cart) }
        if r.bool("MissingCart3dImage") { missing.insert(.cart3D) }
        if r.bool("MissingManual") { missing.insert(.manual) }
        if r.bool("MissingBannerImage") { missing.insert(.banner) }
        if r.bool("MissingMusic") { missing.insert(.music) }

        self.init(
            id: id,
            title: title,
            platform: r["Platform"] ?? "",
            applicationPath: r["ApplicationPath"] ?? "",
            sortTitle: r["SortTitle"],
            developer: r["Developer"],
            publisher: r["Publisher"],
            releaseDate: r.date("ReleaseDate"),
            genres: r.list("Genre"),
            series: r.list("Series"),
            playMode: r["PlayMode"],
            rating: r["Rating"],
            starRating: r.double("StarRatingFloat") ?? r.double("StarRating") ?? 0,
            communityStarRating: r.double("CommunityStarRating"),
            communityStarRatingVotes: r.int("CommunityStarRatingTotalVotes") ?? 0,
            notes: r.text("Notes"),
            commandLine: r["CommandLine"],
            configurationPath: r["ConfigurationPath"],
            configurationCommandLine: r["ConfigurationCommandLine"],
            rootFolder: r["RootFolder"],
            manualPath: r["ManualPath"],
            musicPath: r["MusicPath"],
            videoPath: r["VideoPath"],
            dosBoxConfigurationPath: r["DosBoxConfigurationPath"],
            emulatorID: r["Emulator"],
            favorite: r.bool("Favorite"),
            installed: r.bool("Installed"),
            completed: r.bool("Completed"),
            hidden: r.bool("Hide"),
            broken: r.bool("Broken"),
            portable: r.bool("Portable"),
            playCount: r.int("PlayCount") ?? 0,
            playTimeSeconds: r.int("PlayTime") ?? 0,
            lastPlayed: r.date("LastPlayedDate"),
            dateAdded: r.date("DateAdded"),
            dateModified: r.date("DateModified"),
            databaseID: r.int("DatabaseID"),
            wikipediaURL: r["WikipediaURL"],
            videoURL: r["VideoUrl"],
            source: r["Source"],
            status: r["Status"],
            region: r["Region"],
            version: r["Version"],
            releaseType: r["ReleaseType"],
            maxPlayers: r.int("MaxPlayers"),
            cloneOf: r["CloneOf"],
            useDosBox: r.bool("UseDosBox"),
            useScummVM: r.bool("UseScummVM"),
            missingMedia: missing
        )
    }
}

nonisolated extension AlternateName {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let gameID = r["GameID"], let name = r["Name"] else { return nil }
        self.init(gameID: gameID, name: name, region: r["Region"])
    }
}

nonisolated extension AdditionalApplication {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let id = r["Id"], let gameID = r["GameID"] else { return nil }
        self.init(
            id: id,
            gameID: gameID,
            name: r["Name"] ?? "",
            applicationPath: r["ApplicationPath"] ?? "",
            commandLine: r["CommandLine"],
            autoRunBefore: r.bool("AutoRunBefore"),
            autoRunAfter: r.bool("AutoRunAfter"),
            waitForExit: r.bool("WaitForExit"),
            playCount: r.int("PlayCount") ?? 0,
            playTimeSeconds: r.int("PlayTime") ?? 0
        )
    }
}

nonisolated extension Platform {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let name = r["Name"] else { return nil }
        self.init(
            name: name,
            category: r["Category"],
            releaseDate: r.date("ReleaseDate"),
            developer: r["Developer"],
            manufacturer: r["Manufacturer"],
            notes: r.text("Notes"),
            imageType: r["ImageType"],
            folder: r["Folder"],
            sortTitle: r["SortTitle"]
        )
    }
}

nonisolated extension PlatformCategory {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let name = r["Name"] else { return nil }
        self.init(name: name, nestedName: r["NestedName"], notes: r.text("Notes"))
    }
}

nonisolated extension PlatformFolder {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let platform = r["Platform"], let mediaType = r["MediaType"], let folderPath = r["FolderPath"] else {
            return nil
        }
        self.init(platform: platform, mediaType: mediaType, folderPath: folderPath)
    }
}

nonisolated extension ParentLink {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        let child: LibraryEntityRef
        if let name = r["PlatformName"] {
            child = .platform(name)
        } else if let id = r["PlaylistId"] {
            child = .playlist(id)
        } else if let name = r["PlatformCategoryName"] {
            child = .category(name)
        } else {
            return nil
        }
        var parent: LibraryEntityRef?
        if let name = r["ParentPlatformName"] {
            parent = .platform(name)
        } else if let id = r["ParentPlaylistId"] {
            parent = .playlist(id)
        } else if let name = r["ParentPlatformCategoryName"] {
            parent = .category(name)
        }
        self.init(child: child, parent: parent)
    }
}

nonisolated extension Playlist {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let id = r["PlaylistId"], let name = r["Name"] else { return nil }
        self.init(
            id: id,
            name: name,
            nestedName: r["NestedName"],
            sortTitle: r["SortTitle"],
            notes: r.text("Notes"),
            autoPopulate: r.bool("AutoPopulate"),
            includeWithPlatforms: r.bool("IncludeWithPlatforms")
        )
    }
}

nonisolated extension PlaylistFilter {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let fieldKey = r["FieldKey"], let comparison = r["ComparisonTypeKey"] else { return nil }
        self.init(fieldKey: fieldKey, comparison: comparison, value: r["Value"] ?? "")
    }
}

nonisolated extension PlaylistGame {
    public init?(record: LaunchBoxRecord) {
        let r = record.reader
        guard let gameID = r["GameId"] else { return nil }
        self.init(
            gameID: gameID, title: r["GameTitle"], fileName: r["GameFileName"],
            platform: r["GamePlatform"], manualOrder: r.int("ManualOrder") ?? -1)
    }
}
