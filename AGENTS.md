# Silverbox

A SwiftUI front-end for the eXoDOS / eXoWin9x game preservation collections on
macOS. It reads an eXoDOS installation (LaunchBox XML, images, manuals, music,
videos, game archives) in place and launches games in DOSBox Staging or
DOSBox-X with a translated config.

The goal is a Mac client for these collections, similar to LaunchBox on
Windows: it reads the eXoDOS / LaunchBox configuration files so that an
eXoDOS installation or download is usable on the Mac. The actual emulators
(DOSBox and related) are external to this front-end project.

Names: the project, app target, app module and source folder are all
`Silverbox`; the core library is `SilverboxCore`. The local data folder is
`~/Library/Application Support/Silverbox`. The bundle identifier is
`app.getsilverbox.Silverbox`.
The display name is "Silverbox"; it is set once in `AppInfo`
(`SilverboxApp.swift`) and in the `PRODUCT_NAME` and
`INFOPLIST_KEY_CFBundleDisplayName` build settings, so the built app is
`Silverbox.app`. Credit the eXo project in the About box. Do not describe
the app as a collection of classic Mac games.

## Layout

- `Sources/SilverboxCore/` — the portable core: Foundation only, no AppKit/SwiftUI.
  LaunchBox XML parsing, library snapshot and queries, media lookup, DOSBox
  config translation, launch planning, installing, Lite game downloads,
  user state, music decoders. Every type here is marked `nonisolated` because the app target
  uses MainActor as the default isolation; the package build enforces the
  same rule. Anything the app uses must be `public`.
- `Sources/CStbVorbis/`, `Sources/CXmpLite/` — vendored C decoders (Ogg
  Vorbis; MOD/S3M/XM/IT modules), each its own package target with the
  upstream `LICENSE` and a `VENDOR.md` note.
- `Silverbox/App/`, `Silverbox/Views/`, `Silverbox/Services/` — the Mac app. Every
  file imports `SilverboxCore`.
- `Tests/SilverboxCoreTests/` — Swift Testing suites for the core, with a small
  LaunchBox-style library and audio samples under `Fixtures/`. Tests in
  `RealLibraryTests.swift` run only when `/Volumes/eXoDOS_ro` (or
  `$SILVERBOX_TEST_LIBRARY`) exists.
- `docs/site/` — the website, getsilverbox.app: static HTML and CSS on
  GitHub Pages (`.github/workflows/pages.yml`), built like Silverside's
  site. Its README covers the files, publishing and screenshots
  (`make site-shots`, from the scenes in `docs/site/tools/scenes`). Keep
  its claims in step with the README and the help. The update feed,
  `docs/site/appcast.xml`, is written only by `make dist`.
- `Packaging/` — what `make dist` uses: `ExportOptions.plist` (Developer
  ID export) and the disk image's window (`dmg_settings.py`, the
  background pictures and the script that draws them).
- `scripts/` — `version.sh` (the version; `make lint` checks it),
  `dist.sh` (`make dist`), `release.sh` (a release, run by the maintainer
  only), `check_feed.py`, and the build phases' scripts. A release is in
  `docs/internal/Releasing.md`.
- `Package.swift` at the repo root defines the `SilverboxCore` library and the
  vendored C targets. The Xcode app target links the `SilverboxCore` product as a
  local package dependency (the repo root added through File › Add Package
  Dependencies › Add Local), so the core is compiled once, by the package.

## Build and test

```
make run [ARGS='...']            # xcodebuild the app, then start it in the foreground
make build                       # app only (CONFIG=Release for a release build)
make test                        # swift test: core tests (fast; real-library tests if mounted)
make core                        # swift build: core only
make sweep                       # translate every eXoDOS config in the mounted library, print a summary
make format                      # swift-format the Swift sources (settings in .swift-format)
make lint                        # report formatting, trailing whitespace and version problems without changing files
make install-app                 # universal Release build copied to ~/Applications (APP_DIR=... elsewhere)
make open-app                    # install-app, then open the app (quit the installed copy first)
make reset                       # delete the app's settings and local data folder (asks first; YES=1 skips)
make dist                        # Developer ID, notarized disk image and update feed in build/dist (see Releasing.md)
make site                        # serve the website (docs/site) at http://localhost:8001
make site-shots                  # take the site's screenshots again, scene by scene (you capture each window)
```

Never run `scripts/release.sh`, tag, push or publish a release: the
maintainer does those by hand. Never run make as root.

`make run` resolves the built app through `xcodebuild -showBuildSettings`,
so it shares Xcode's DerivedData.

If an Xcode MCP server is connected, use it to build, read diagnostics and
change build settings; otherwise build with `make build`. Do not edit
`project.pbxproj` by hand. New files under `Silverbox/` are picked up
automatically; files under `Sources/` and `Tests/` belong to the package.
The Xcode project has only the app target: all tests are in the package.

To check that the app sources still compile against the core without Xcode,
type-check them against the package build (see the `typecheck` target in the
Makefile).

Run `make format`, `make lint` and `make test` (and build the app) before you
report work as done.

`CHANGELOG.md` has an entry for each version, for people who use the app:
Added, Changed and Fixed, in plain words, with no internal names. When you
change what a user sees or can do, add a line to the newest entry. Start a
new entry after the version is tagged; the version is the app target's
`MARKETING_VERSION`. The milestones and what is still to do are in
`docs/internal/Milestones.md`; keep it and the README's "To do" up to date.

Commit messages: a subject line, a blank line, then paragraphs. Hard-wrap
the body at about 75 characters, and break lines between words, never
inside a path or code span.

## Conventions

- Keep core code free of Apple-only frameworks so it can later back a
  SwiftCrossUI client on Linux. Platform-specific work (unzip binary paths,
  emulator locations) stays behind small helpers with `#if os(...)`.
- Formatting. `make format` runs `swift-format` with the settings in
  `.swift-format` (4-space indent, 120 columns, sorted imports). Run it after
  changing Swift files and before the work is reviewed or committed; do not
  hand-wrap code that the formatter will rewrite.
- Collections. The app loads several `LibraryCollection`s (LaunchBox-format
  libraries: eXoDOS mirrors, the console LaunchBox install) into one `Library`
  aggregate of `LibrarySnapshot`s. `Game.id` is collection-scoped
  (`<collectionID>/<launchBoxID>`) because the same GUIDs appear in several
  copies of a library; user state is keyed by `launchBoxID`. Each collection
  has path substitutions (Windows prefix to Mac folder) for relocated `Games`
  folders and drive-letter paths. Parsed libraries are cached as JSON under
  `LibraryCache/` keyed by the data files' sizes and dates; "Rescan" clears it.
  When a volume that holds a collection, its download or the local data
  folder mounts or unmounts, `AppModel.volumeChanged` waits 3 s, then
  reloads if a collection had not loaded or the data folder was out of
  reach, and otherwise only refreshes `rootReports`. On
  `willUnmountNotification` (a Finder eject), `releaseFiles(on:)` closes
  what Silverbox holds open there (the menu music, even paused; an album;
  Quick Look; `GameVideoPlayer` through `releasingVolume`) so the eject
  is not refused, and the music comes back when the volume mounts again
  or after 10 s if it stays. `AppModel+Volumes` records each network
  share's `volumeURLForRemounting` in `settings.remountURLs` (keyed by
  mount point) after a load and a mount; Try Again and Settings'
  Connect mount the missing ones with `NetFSMountURLAsync` (password
  dialog allowed), and the mount notification reloads.
- Two roots. Every library (collection folder) is read-only as far as the app is
  concerned; it may live on a read-only volume. Everything bulky the app writes
  goes to the local data folder (`LocalStore` plus `AppPaths.dataRoot`, default
  `~/Library/Application Support/Silverbox/`, movable to another drive in
  Settings; `user-library.json` and the settings always stay in Application
  Support): `Games/` (unpacked games; mirrors `eXo/`, so `Games/eXoDOS/<folder>`
  and `Games/eXoWin9x/<year>/<folder>`),
  `Saves/Installations/<installation key>/` (backups of changed files made on uninstall; older backups in `Saves/` are still restore sources), `Overrides/<gameID>/`
  (edited configs), `Overlay/` (also mirrors `eXo/`: `eXoDOS/` overlay mounts
  for games unpacked inside a read-only library, copies of eXoWin9x game disks,
  and the Windows 98 differencing disks under `emulators/`), `Soundtracks/`
  (albums unpacked from the library's zips), `Launch/`, `Logs/`, `MediaIndex/`,
  `BitTorrent/` (aria2's DHT table), `MAME/` (eXoAppleIIGS: copies of eXo's
  MAME settings and IIGS memory, and in `roms/` the ROM the user adds),
  `user-library.json`. "Install in place"
  (into `eXo/eXoDOS`) is an option. Game downloads are the one exception:
  they go into the collection, as on Windows (see Lite downloads).
- Emulators. `EmulatorKind` covers DOSBox Staging and DOSBox-X for eXoDOS
  games, 86Box (`.box86`) for some eXoWin9x games, GSplus for eXoAppleIIGS,
  plus RetroArch, Dolphin, MAME and Mednafen for console, computer and
  arcade platforms (`Game.launchKind` tells them apart). Each platform's
  emulator comes from `EmulatorAssignmentResolver`: the user's choice in
  Settings, else the library's `Emulators.xml` mapped to the Mac emulators
  that are installed (`RetroArchSetup` finds cores through `retroarch.cfg`,
  with aliases for renamed cores). `RomLaunchPlanner` builds the command
  line. Never call another front-end such as OpenEmu.
  BIOS files: `RetroArchSetup.firmware(forCore:)` reads the core's `.info`
  list; `RomLaunchPlanner.firmwareCheck` copies the missing ones from the
  library's own RetroArch (`libraryRetroArchSystemDirectory`: its
  `retroarch.cfg`'s `system_directory`, else `system` beside
  `retroarch.exe`) into RetroArch's system folder, never replacing a
  file (`EmulatorLaunch.fileCopies`), and the inspector's "BIOS missing"
  chip names required ones found nowhere. Never pass RetroArch
  `--appendconfig`: with `config_save_on_exit` (the default) it saves the
  appended settings into the user's `retroarch.cfg` when it quits.
- eXo packs. `EXoPack` names the projects whose games install from zips:
  eXoDOS (`!dos/<folder>`, unpacked to `eXoDOS/<folder>`), eXoWin3x
  (`!win3x/<folder>`, eXoDOS-shaped; each game zip holds its own Windows 3.1),
  eXoWin9x
  (`!win9x/<year>/<folder>`, unpacked to `eXoWin9x/<year>/<folder>`),
  eXoDemoScene (`eXoDemoScn/!demoscn`), eXoScummVM (`!ScummVM`),
  eXoAppleIIGS (`!appleiigs`) and eXoIF (`!IF`); the pack comes from the
  game's `RootFolder`. `Game.installPath` is the unpacked folder relative to
  `eXo/`; installed-game sets in `LibrarySnapshot` use it, matched without
  regard to case (some zips unpack to another case). `isDOSGame` is true for
  the DOSBox packs (eXoDOS, eXoWin3x, eXoDemoScene). eXoDOS and eXoDemoScene
  have a build index (`dosbox.txt`, `demoscn.txt`); eXoWin3x's launchers name
  the build (`.\dosbox\ece\dosbox.exe`; `svn` is Daum, `svn_2` Staging), so
  the loader builds its index with `DOSBoxIndex.fromLaunchers(in:)`.
  `isEXoGame` is for installing. Folders that
  differ per pack go through `gamesDirectory(for:)`, `overlayDirectory(for:)`
  and `dosboxIndex(for:)`. Each pack's `Setup <pack>.bat` entry is hidden
  (`isEXoSetupScript`). The sidebar's "eXo Packs" section (`LibraryScope.pack`)
  appears when more than one pack is loaded.
- eXoWin9x. `launchKind == .windows9x`. `LaunchPlanner.planWindows9x`
  (`Windows9xLaunch.swift`) reads `Play.conf`: DOSBox-X boots Windows 98 from
  a differencing disk (`vhdmake`) over `eXo/emulators/dosbox/x98/parent/*.vhd`,
  with the game's VHD as D: and its CDs as E:. The differencing disk goes to
  `Overlay/emulators/dosbox/x98`; a game disk on a read-only library is copied
  to `Overlay/` once. Games with `Network.ps1` get its Solo settings. Games
  with only `Play.cfg` run in 86Box (`plan86Box`): the paths in it are
  relative to `eXo/emulators/86Box98`, and `VHDDifferencingDisk` writes the
  fresh child disk that eXo makes with `makevhd.exe`.
- Setup. A Mac user can add an untouched eXo download: `EXoDownload`
  finds the packs (`Content/!<pack>metadata.zip`), metadata, media add-ons,
  `Content/GameData` and `eXo/util/util*.zip`; `EXoSetup` does what eXo's
  `Setup <pack>.bat` does without Windows: unpacks them (nested `EXT*.zip`
  into `eXo`, `OPT*.zip` into `eXo/util`), merges the XML fragments by
  reading the `xml/merge_*.bat` scripts, registers add-on platforms as
  `eXoLBpm.exe` would, and writes `Data/Silverbox Setup.json`. It sets up
  in place or, by choice or when the download is read-only, into
  `Collections/<name>-<source key>` in the local data folder (existing named folders are reused only when their recorded source matches) with
  `LibraryCollection.downloadPath` pointing back (`LibraryRoot.downloadFile`
  finds game zips and extras there). Settings stores absolute paths, so
  `AppModel.setDataFolder` moves the collections inside the old data folder
  to the new one when they are there
  (`LibraryCollection.following(dataFolderFrom:to:)`). A game's
  GameData zip is unpacked at install when setup left it packed.
  `ZipArchive` extracts with `unzip`, or `bsdtar` when the entries to
  extract have names in the DOS code page (CP437) without the UTF-8 flag,
  which eXo's zips have. Setup skips `.exe` and `.dll` files under
  `emulators/` (eXo's Windows emulator builds). Packs without GameData zips
  keep each game's `Extras` folder in the config archive until install,
  when "unpack each game's when installed" is chosen
  (`InstallPlan.extrasPatterns`). eXoWin3x is set up the older way: no
  `merge_platforms.bat`, so `Platforms.xml` and `Parents.xml` come from
  `Content/LaunchBox.zip` (`copyLaunchBoxPlatforms`); its family list is
  `xml/WinFAMILY.xml`, copied over `Windows 3x.xml`; util3x.zip nests
  `mt32.zip` (unpacked into `eXo`) beside Windows DOSBox builds and shaders.
  Its banner entry, titled `eXoWin3x` with no launcher, is hidden like the
  setup scripts.
- eXoScummVM. `launchKind == .scummVM`. `ScummVMLaunch.swift` follows eXo's
  `launch_svm.bat`: `ScummVMIndex` reads `eXo/util/scummvm.txt` (prefix
  match, last line wins); variants are the folders in the installed game
  (a folder with `menu.txt` gives sub-variants, id `Parent/Sub`); each
  variant's `platform.txt`, `video.txt`, `audio.txt`, `subtitle.txt` and
  `sound.txt` become options, and the music and subtitle answers are
  `LaunchChoices`, remembered per game. Settings live in the local
  `ScummVM/scummvm.ini` (eXo's global settings once, plus the targets eXo
  defines, such as `kq6-cd`), saves in `Saves/ScummVM`. `.scummVMDaily` is an
  optional second ScummVM for engines the release build lacks
  (`AppModel+ScummVM` checks `--list-engines`).
- eXoIF. `launchKind == .interactiveFiction`. `IFLaunch.swift` follows eXo's
  `launch_if.bat`: versions are the folders in the installed game (a folder
  with `menu.txt` and no `ignoremenu.exo` gives sub-versions); the file to
  run is the only file, else `dosbox.conf`/`dosbox-x.conf`, else
  `launch.file`; `IFSystemTable` reads the folder-name-to-emulator table from
  `launch_if.bat` itself. `IFRoute`: MS-DOS versions go through
  `planDOSBox`, interpreter versions (WinFrotz, Lectrote, Gargoyle and the
  like) open in Spatterlight with `open -W -a` (it ignores files passed as
  arguments), 8-bit versions go to the RetroArch cores in
  `ifRetroArchCores` (a VICE `fliplist.vfl` becomes an m3u playlist;
  atari800 gets eXo's Altirra ROMs copied into RetroArch's system folder
  where missing; PUAE needs a Kickstart there),
  everything else is `unsupported` (`LaunchVariant.unsupportedReason`, which
  also names a missing core or ROM). The app's `launchPlanner(_:)` passes
  `settings.retroArchSetup`. The default version is the best `preference`:
  Spatterlight, then DOS, then RetroArch.
- eXoAppleIIGS. `launchKind == .appleIIGS`. `AppleIIGSLaunch.swift` follows
  eXo's `Launch_IIGS.bat`: `AppleIIGSIndex` reads `eXo/util/appleIIGS.txt`
  (`findstr` match, last line wins) for the route: GSplus (376 games),
  GSport (10, whose `config.txt` is in the unpacked game; GSplus runs them)
  or MAME (74). `AppleIIGSException` reads `exception.bat`: its `SET`
  variables (`CONFIGTXT` for GSplus; `DISK1`-`DISK3`, `DISKS`, `SPEED`,
  `PRINTER` for MAME), a menu of choices that set them (versions), and the
  `echo` text (`LaunchVariant.note`, shown in the launch options).
  - GSplus: the Mac GSplus 1.38 (KEGS) takes `-cfg <file>`, changes to the
    config's folder and writes the file back, so `GSplusConfigTranslator`
    writes a fresh `Launch/<id>-gsplus/config.kegs` each time: absolute
    disk paths (found without regard to case; `#name` and missing disks
    left empty, as GSplus on Windows skips them), the ROM in
    `eXo/emulators/GSPlus`, GSport's keypad joystick as Auto, no status
    lines, and the full-screen choice.
  - MAME (`planAppleIIGSMAME`): eXo ships Windows MAME 0.245 with a
    matching ROM set; current MAME also needs `344s0047.bin`, which no one
    may ship, so the user adds it (Settings › Emulators › Add ROM…;
    `AppleIIGSCharacterROM.importFile` checks the SHA-1, also inside a
    zip) into `MAME/roms/apple2gs/`; until then `appleIIGSProblem(for:)`
    is the variants' `unsupportedReason` and the chip says "ROM missing".
    Homebrew MAME runs with `-noreadconfig` (eXo's `mame.ini` is for
    Windows), that folder and eXo's `roms` as the ROM path, and eXo's
    `apple2gs.cfg` (the `fast` one for `SPEED=TRUE`) and `apple2gs/`
    memory copied to `MAME/cfg` and `MAME/nvram` once.
  - Disks of a game unpacked in a read-only library are copied to
    `Overlay/eXoAppleIIGS` once.
- Favorites. In an eXo pack's XML, `Favorite` marks eXo's picks
  (`Game.isEXoFavorite`, the `.eXoFavorites` scope, "eXo Favorites" in the
  sidebar), not the user's. The user's favorites are
  `UserLibraryState.isFavorite`: the user's choice, else
  `Game.isFavoriteByDefault`, which is the XML flag only outside the eXo
  packs (a LaunchBox library's own favorites). Each copy of a game is a
  favorite on its own. Playlist filters on `Favorite` still read the XML.
- Other versions. `GameVersionIndex` (core, `GameVersions.swift`) groups
  games by a title key (case, accents, punctuation, a leading article and a
  trailing note in brackets left out) and links two games when they also
  share a word of their developer or publisher names (common words such as
  "Software" or "Freeware" do not count) or the LaunchBox database id.
  Documents, links, soundtracks and videos are left out. The app builds it
  with the search index at load; `OtherVersionsMenu` in the context menu
  lists the matches and `AppModel.reveal(_:)` selects one, clearing the
  search or widening the scope to the game's pack when needed.
- Media. `MediaCatalog` finds images by LaunchBox's naming
  (`<sanitized title>[.<game id>]-<NN>.<ext>`, region sub-folders). When no
  file is named after the title, one named after the ROM file
  (`Game.launcherBaseName`) counts, as LaunchBox allows; Skraper and
  EmuMovies name media that way. Videos, manuals and music already match by
  launcher name first, then title. A saved image index
  (`MediaIndexStore`) is reused while the folder and each sub-folder keep
  their modification dates (`MediaFolderIndex.isCurrent`).
- Thumbnails. `ThumbnailCache` (app) decodes images at a pixel size and
  keeps 800 in memory; sizes up to 600 px also go to
  `ThumbnailDiskCache` in `AppPaths.thumbnails`
  (`~/Library/Caches/<bundle id>/Thumbnails`, local even when the data
  folder is not), keyed by the image's path and size and never checked
  against the original, since that check is what costs on a share. JPEG
  for opaque, downscaled images, PNG otherwise; the least recently used
  go past 300 MB. Rescan Library clears both. Measured on the eXoDOS
  share: about 390 ms per grid cover from the share while scrolling, 0.3
  ms from the disk cache.
- Soundtracks. Entries whose launcher is foobar2000 with a zip argument are
  `launchKind == .soundtrack`. `SoundtrackLibrary` (core) resolves the zip,
  lists it with `unzip -Z1` and unpacks it; `AlbumPlayer` (app) plays the
  files, `AlbumBar` replaces the music bar while it does, and
  `AppModel+Soundtracks` holds the cache and the unpack-on-play flow.
- MIDI menus. eXo's in-game batch menus run `CONFIG -set
  "mididevice=default"` for General MIDI, which DOSBox Staging rejects (it
  falls through to CoreMIDI). For Staging, `planDOSBox` has
  `MIDIBatchPatcher` rewrite that line in the game's `.bat` files (two
  levels deep) to `ConfigTranslator.generalMIDIDevice`, keeping the original
  in a `rem Silverbox replaced:` line so a later choice rewrites it again.
  The patched file goes in place for local installs and under the overlay
  folder for read-only libraries (`LaunchPlan.filePatches`, written by
  `writeConfig`); a writable library is left alone, with a note.
- Launch logs. `GameLauncher` writes each emulator's output to `Logs/`;
  `AppModel.lastSessions` keeps the last `GameSession` per game, so "Show
  Last Launch Log…" (context menu) and "Show Log" (the now-playing bar)
  open `LaunchLogSheet`. A non-zero exit opens it by itself. "Copy as
  Markdown" builds a `LaunchReport` (core, `LaunchReport.swift`) from the
  session, the config at `EmulatorLaunch.configURL` and the log's end.
  RetroArch runs with `--verbose`, so the log has its and the core's
  messages (a missing BIOS). After a start, `GameLauncher` brings the
  emulator to the front once it is an app, if Silverbox is still in front:
  RetroArch otherwise opens behind and pauses.
- Lite downloads. eXoDOS Lite has no game zips or GameData zips; it ships
  the full collection's torrent in `eXo/util/aria/` (`LibraryRoot.torrentURLs`),
  which setup unpacks from `OPTDOS.zip` inside `util.zip`; a full download
  has it too. `TorrentFileList` (core,
  `Download/Torrent.swift`, with a small bencode reader) numbers the files
  as aria2's `--select-file` does. `GameInstaller.downloadPlan(for:)` finds
  the missing `eXo/<pack>/<name>.zip` and its
  `Content/GameData/<pack>/<name>.zip` in it, by the same paths the
  installer looks for; the files go to those paths in the collection, so
  the collection must be writable. `TorrentDownloader` runs aria2c (an
  external program from Homebrew, found by `discover()`, never bundled)
  with eXo's flags (`--seed-time=0`), each file written as `<number>.zip`
  in `eXo/DOWNLOAD/<torrent>-<numbers>/` and moved into place when done;
  a stopped download keeps that folder and its `.aria2` control file and
  resumes. Progress comes from the console readout
  (`--human-readable=false`), whose totals count 8 MB pieces, so the app
  shows only its fraction of the plan's size. Many of the torrent's
  trackers are dead and aria2 announces to one at a time, so the first
  download can take a minute to find peers; the DHT table in
  `BitTorrent/dht.dat` (with `dht.transmissionbt.com` as the entry point)
  makes later ones start in seconds. `plan(afterDownloading:for:)` unpacks
  a downloaded GameData zip that the plan would not otherwise unpack.
  `AppModel+Downloads` runs one download at a time (`DownloadGate`); the
  install sheet says why a download cannot start.
- Background jobs. `InstallRun` (observable) drives one installation:
  `AppModel.startInstall` downloads a missing archive first (see Lite
  downloads), then runs `GameInstaller.install` with its progress
  closure, `JobsBar` shows the runs above the now-playing bar, Cancel stops
  the download (which resumes on the next try) or the unzip (and removes
  only that run's hidden staging folder), `DockProgress` draws the mean
  progress on the Dock tile, and `JobNotifier` bounces and notifies when a
  job finishes while the app is in the background. Setup reports through
  the same two services.
- File operations. `FileOperationCoordinator` reserves physical paths (including
  aliases and ancestor folders) for installing, uninstalling and setup. A
  `GameLauncher` session holds the launch plan's reservation from before
  `writeConfig` until the emulator exits, including shared Win9x VM files.
  Installations publish a staged game folder only on success and never
  replace an existing installation. Quitting with games or jobs running asks
  first (`applicationShouldTerminate`); "Quit Anyway" cancels the jobs and
  waits up to 15 s for them to remove their staging folders. Games stay
  open: each reserved launch is recorded in `running-games.json` (beside
  `user-library.json`; `RunningGameLedger`) with its process number, start
  time and paths, and at the next start `GameLauncher` reserves the paths
  again for each emulator still running (`adopted`) until it exits. A game
  installed in the collection's own folder has a backup key from the
  absolute path, so its backup has a `<name>.json` beside it
  (`SaveBackupSource`: collection ID, game ID, folder in the collection);
  when no backup is at a known place, `LocalStore.movedSaveArchive` offers
  the one backup whose record matches, for a remounted volume.
  User-state changes go through `UserLibraryStatePersistence`: enqueue the
  latest state, serialize flushes, preserve unreadable originals and flush
  before normal termination; a failed flush offers "Quit Anyway", and when
  the file could not be read or kept aside nothing is saved at all.
- Sidebar. Rows carry `.badge` counts from `AppModel.sidebarCounts`,
  recounted off the main thread shortly after the library or the user's
  state changes (playlists are not counted); each collection's header shows
  its count of titles (games, and the books, magazines, soundtracks and
  videos beside them; `Game.isGame` tells them apart) and "read-only",
  the same line as in Settings › Library, and `DataFolderFooter` shows
  the local data folder. A playlist's row drops the words above it
  (`LibraryNode.sidebarTitle(under:packs:)`: "MT-32" for "eXoDOS Games
  with MT-32", "Installed Demos" for "Installed eXoDemoScene Demos"; a
  pack's name goes from anywhere in the title, a row's title only from
  the start) and has the whole name as its help. Empty states use
  `ContentUnavailableView`.
- Search. It stays in the selected scope, so the subtitle counts against
  `AppModel.scopeGameCount`, and `LibraryQuery.rankedBySearch` orders
  the result by `SearchRank`: a term that is a word of the title, then
  the start of a word ("Ultima" before "Ultimate"), then inside a word,
  then the matches by developer, publisher or another name.
- Back and Forward. `NavigationHistory` (core) keeps the places the
  window showed; `AppModel+History` says what a place is
  (`NavigationPlace`: scope, search, open page, selected game) and when
  one is left: the observers of `scope` and `openedGameID`, and of
  `searchText` when a search starts or ends, call `leftPlace`. Moving
  the selection makes no entry. A step that changes several of these
  goes in `navigate { }` (the sidebar, `reveal(_:)`), so it is one entry.
  `navigateBack()` and `navigateForward()` pass over a place whose
  section or game is gone. The toolbar's arrows, Command-[ and Command-]
  (Library menu) and `HistoryKeys` (mouse buttons 4 and 5, Command-Left
  and Command-Right outside a text field) call them.
  `closeGamePage()` (Escape, Command-Up) is Back when the page was opened
  from the list on show, so Forward opens it again. `closeTopmost()` is
  Escape's order of things to close, which is another thing. A grid that
  is new scrolls to its selection again once its tiles exist.
- Game page. `GameDetailView` takes the content column (Command-Down, the
  inspector's button). The inspector is hidden beside it
  (`AppModel.inspectorHasAPlace`) and comes back with the library, so the
  page has the status chips and the favorite and edit buttons itself.
  `MainActionStyle` draws Install and Play in the accent; Play's version
  menu is its trailing segment, drawn by the menu's label, because a
  `Menu` takes neither `.borderedProminent` nor a custom button style.
- List view. Column headers for Title, Year and Developer sort through
  `settings.sortOrder` and `settings.sortAscending`, the same settings as
  the toolbar's Sort menu; `Game.sortYear` and `sortDeveloper` give
  `KeyPathComparator` non-optional keys.
- About. `AboutView` follows Silverside's About window: the icon on a dark
  CRT band (`CRTHero`, like the website's), an accent rule, name and
  version (a click copies `AppInfo.versionLine`; the commit is in its
  help), library counts from `sidebarCounts`, the eXo credit with the
  eXoDOS cover, Acknowledgments, Website and Leave a Tip buttons, and the
  copyright with a link to Silvercode Studio. The addresses are in
  `SilverboxLinks` (core): the website (also Help › Silverbox Website),
  the studio, and the studio's tip page with `?from=silverbox` (also Help
  › Support Silverbox). The tip link is in no other place in the app, so a
  free app does not nag. `AcknowledgmentsSheet` has the License… button
  for `LicenseSheet`; the texts come from `Silverbox/Licenses/*.txt`,
  copies of the repository's `NOTICE`, `LICENSE` and the vendored
  decoders' licenses that `ProjectFilesTests` keeps identical, and
  Sparkle's `LICENSE`. The license is the GNU GPL; the name and icon
  artwork are not covered by it.
- Updates. Sparkle (2.10.1, the app target only) through `AppUpdater`,
  which starts only in an archive (`SilverboxArchive`), so a build from
  source never replaces itself. Check for Updates… in the app menu and
  Settings › General › Updates. `AppModel.postponeRelaunch` holds an
  update's relaunch while `hasWorkUnderWay` (jobs, running games, and
  any `FileOperationCoordinator` reservation) and says so once.
  `Silverbox/Info.plist` has the signed feed's URL
  (`getsilverbox.app/appcast.xml`) and public key; the build phase
  "Remove Sparkle's XPC services" (`scripts/remove-sparkle-xpc.sh`)
  strips them from an archive. `AppUpdater` compiles without the package
  (`canImport`); `make dist` refuses such an app.
- Version and commit. The app target's "Record the Git commit" build phase
  runs `scripts/record-commit.sh`, which writes `scripts/commit-id.sh`'s
  commit (`c2b2f09`, `-dirty` with uncommitted changes) into the built
  Info.plist as `SilverboxCommit`, and `SilverboxArchive` for an archive.
  `AppInfo.versionLine` ("Silverbox 0.5 · c2b2f09") goes into launch
  and problem reports; the About window shows the version alone, with
  the commit in the line's help. The phase needs the target's user script sandboxing off.
- Reports. Help › Report a Problem… and Send Feedback… open GitHub's new
  issue and new discussion pages for `ProblemReport.repository`, filled in
  by `ProblemReport` (core) from `AppModel+Reports`: the version, the Mac,
  each collection's packs and game count, and the emulators found. No
  paths or collection names. The app sends nothing itself; the privacy
  page says so.
- Status. The accent (amber) is for actions and selection: the main
  button, the selection, links (`.accentLink()`). Status never takes it.
  A status has a glyph in a tone (`StatusTone`: `Theme.good`, `.warning`,
  which is yellow, or `.bad`) and its text in a text colour: `StatusLabel`
  for a line, `Chip` and `ChipRow` (`Chips.swift`) for a capsule, both
  through `StatusGlyph`, which draws the warning triangle with a dark "!"
  on its yellow (the yellow alone is too pale on a light window). Use
  these for status, never `.red` or `.orange`, and never
  `Label(…).foregroundStyle(Theme.warning)`. `GameStatusChips`
  in the inspector header says whether the game is installed, which
  emulator runs it and whether that emulator is present. Keep chip text to
  a few words and put the whole reason in its `help`; a control that is
  disabled says why in `.help` too.
- Focus. Windows and sheets open with `.withoutInitialFocus()`
  (`WindowFocus.swift`), so that keyboard navigation in System Settings
  does not put a focus ring on the first button or link.
- Settings text. A group's note is one sentence; the details go in help
  page 05. A pop-up button that could also take any folder or app has
  "Other…" as its last entry (the video player, the local data folder),
  not a Choose… button beside it. The welcome's data folder step is the
  exception: it shows the folder with Choose… and Use Default, because a
  first-time user is to see the path and both actions at once. An
  emulator shows as an app (`EmulatorApp`: name, version, icon), with its
  path as help; a missing one says how many games need it
  (`sidebarCounts.gamesNeeding`, by pack or platform, which follows the
  DOSBox policy and the platform choices; the line's help has the
  breakdown).
- Emulator status. `AppModel.checkEmulators()` records what is installed
  (`EmulatorCheck`) at start, when the app comes to the front and every two
  seconds while Settings › Library, › Emulators, › Display & Sound,
  `WelcomeView` or the install sheet is open (`.watchingForEmulators()`).
  It also finds aria2 (`model.torrentDownloader`, shown by
  `DownloaderStatus`). The check includes FluidSynth for DOSBox Staging (`EmulatorCapabilities`): built into the
  executable since 0.83 (found by scanning it, cached until the file
  changes), else a `libfluidsynth` library in the usual folders;
  `FluidSynthStatus` shows it. Views ask `model.emulatorInstallation(_:)`,
  `model.retroArchSetup` or `emulatorResolver()`, which read the check, not
  `settings.emulatorInstallation(_:)`, so they redraw when it changes.
- First start. With no collection, the content column shows `WelcomeView`,
  under the same `CRTHero` band as the About window, in three steps:
  Add Collection, the local data folder, and the emulators eXoDOS needs
  with aria2 (the other packs' behind a disclosure); a step that is done
  has a check mark (the data folder step unless a chosen folder is out of
  reach, since the default needs no choice). `AppModel.hasGamesToBrowse` is false then and after a
  failed load, and the window leaves out the search, the view controls
  and the inspector. Every Add Collection… button calls
  `AppModel.chooseCollection()`: an open panel with a message, then
  `LibraryFolderChoice.resolve` (core), which takes the collection when
  the folder is a level off (`eXo`, `Data`, or the folder around one
  collection), then `addFolder` (an eXo download or a set-up collection).
  `folderBeingRead` names the folder while that goes on.
- Launching: `LaunchPlanner` maps `eXo/eXoDOS` paths to the local games folder
  for locally installed games, adds overlay mounts for library-installed games
  on read-only volumes, prefers an edited config from `Overrides/`, and layers
  the global `LaunchOptions` plus per-game `LaunchOverrides` (remembered from
  the launch options dialog) on top of the translated config.
- Display font. `Theme.display(size:)` is VT323, the website's headline
  face, for the two big titles only (About's "Silverbox" and "Welcome to
  Silverbox"), never under 32 pt. The file is
  `Silverbox/Fonts/VT323-Regular.ttf` (version 2.000, from
  github.com/google/fonts, `ofl/vt323`; upstream
  github.com/phoikoi/VT323), registered for the process at first use,
  with its license in `Silverbox/Licenses/VT323.txt`. Do not put a
  Markdown note beside it: every `.md` file in the bundle is a help page.
- Help pages are Markdown files in `Silverbox/Help/` (ordered by their numeric
  prefix, title from the first `#` heading), rendered by `MarkdownHTML` in the
  Help window: headings, lists, pipe tables, code and links. Add or edit
  pages there.
- Navigation input. The grid and list handle arrows, Return, Space and
  Escape through SwiftUI focus (`GameGridView`, `GameListView`); media and
  page commands are menu shortcuts in `AppCommands`. `GamepadInput` turns
  controller buttons into the same key presses through `KeyPress.send`, so
  new keyboard behaviour is controller behaviour too. The Quick Look panel
  pages through `AppModel.quickLookItems` (gallery, manual, extras). A new
  shortcut goes in three places: `AppCommands`, `ShortcutReference` (the
  Keyboard Shortcuts window) and help page 07, and in `GameContextMenu`
  when the command is in it: a right-click menu shows the keys
  (`showsKeys`, and `settings.showMenuShortcuts`, off by default), which
  the menu bar's commands carry out. The "…"
  button's menu shows none, because a shortcut in a pull-down `Menu`
  would work a second time. Context menus are AppKit
  menus and do not change once open, so anything loaded for them (the Extras
  submenu) comes from `AppModel.extrasCache`, filled on hover and selection.
- App icon. A floppy disk: `Silverbox/AppIcon.icon` (amber) is the Icon
  Composer file Xcode compiles into the bundle icon;
  `Silverbox/AppIcon-Green.icon` is the alternate, compiled only when the
  target's "Include all app icon assets" is on. The app icon setting shows
  the chosen one in the Dock and the About window through
  `AppIconVariant.image`, which falls back to the flat 1024 px PNGs in the
  `AppIconAmber` and `AppIconGreen` image sets. Icon Composer's `ictool
  --export-image` makes them; make them again when an icon changes. A
  Dock icon set at run time is a flat image, so only the bundle icon
  (amber) follows the system's icon style (dark, clear, tinted). The
  chosen icon also colours the CRT band behind it in the About window
  and the welcome (`AppIconVariant.phosphor`: glow, ground and rule),
  which is decoration. The
  accent is amber with either icon: `Theme.accent` and `Theme.accentText`
  for our own views, and the asset catalog's `AccentColor`, with the same
  light and dark values, for the system's controls. No scene applies
  `.tint`: with it, every pop-up value and button title took the accent.
  Use `Theme.accent`, not `Color.accentColor`, which follows the accent
  the user chose in System Settings. Every `Theme`
  colour has a light and a dark value (`Color(light:dark:)`, a dynamic
  `NSColor`), and the Appearance setting sets `NSApp.appearance`
  (`AppModel.applyAppearance`); do not force a colour scheme on a view. The
  Help page's CSS follows with `prefers-color-scheme`.
- Reference material: a read-only eXoDOS v6 copy at `/Volumes/eXoDOS_ro`,
  LaunchBox screenshots in `Launchbox Screenshots/`, and the design prototypes
  linked from `prompt.md`.

## Verified vs. unverified

- **Verified** with real data: the eXoDOS v6 library at `/Volumes/eXoDOS_ro`
  (`RealLibraryTests`, `make sweep` over every config), the Mac setup of the
  eXoDOS v6 archives against the Windows setup (`matchesTheWindowsSetup`),
  and the downloads of the other packs (`setsUpAndPlansTheDownload`). The
  `LaunchSmoke` tests start eXoDOS games in DOSBox Staging and boot Windows 98
  in DOSBox-X and 86Box. Games confirmed by the user: Marathon 2 (eXoWin9x,
  DOSBox-X) and Locus (eXoWin9x, 86Box); eXoWin3x games boot to Windows 3.1.
  `downloadsFromTheEXoDOSTorrent` downloads a game from the eXoDOS torrent
  with aria2, and `eXoDOSTorrentListsEveryGameArchive` checks the
  torrent's paths against the installer's. eXoAppleIIGS (2026-10-26):
  every GSplus and GSport config's disks against the archives
  (`setsUpAndPlansTheDownload`); ten games booted in GSplus 1.38, one
  (Designasaurus) installed and started from the app; every MAME game's
  disks checked, and Gauntlet installed and started from the app in
  Homebrew MAME 0.289 with the user's `344s0047.bin`. eXoDOS 6.04 Lite
  (the user's download): set up on the Mac, then ZZT's Revenge downloaded,
  installed and played in the app (2026-10-26); its torrent lists all
  7,666 games.
- **Partly verified** (2026-11-20, the user's LaunchBox library,
  RetroArch Nightly): games start in PUAE, AppleWin, atari800, Stella,
  ProSystem and ParaLLEl N64. Hatari, VICE and Mupen64Plus-Next did not
  (see Milestones, M10).
- **Not yet verified:** launches in Dolphin, MAME and Mednafen, most
  RetroArch platforms, and eXoIF's RetroArch versions.
  Say so when a change touches
  these, and do not describe them as working in the README or the help.
- The real-library tests check values read from eXo's own files. Do not
  change them to make a test pass.

## Constraints

- **Dependencies:** ask before adding one. Today there are the two vendored
  C decoders, Sparkle (agreed 2026-11-19, app target only) and the VT323
  font file (agreed 2026-11-20). Declare package dependencies in `Package.swift`
  (remote packages pinned by `Package.resolved`, which is committed);
  dependencies of the app target alone go through Xcode's Add Package
  Dependencies, which the user does. Prefer vendoring small, stable C
  libraries over binary packages or Homebrew: each in its own target under
  `Sources/`, with the upstream `LICENSE` and a `VENDOR.md` that records the
  upstream URL, version or commit, the subset copied and any local changes.
  Never edit vendored files; put wrappers and shims in our own code (a shim
  header in `include/` is fine when it says so). Emulators and `unzip`/`bsdtar`
  are external programs, never linked.
- **Licensing:** the code is under the GNU General Public License, version 3
  or later (`LICENSE`, the FSF's text verbatim). `NOTICE` has the
  copyright notice and what the license does not cover: the name and the
  icon artwork, the vendored decoders and the VT323 font (their own
  licenses), and the eXo
  team's collections and the eXoDOS cover. The app shows the notice, the
  license and the vendored licenses from `Silverbox/Licenses/`, which
  `ProjectFilesTests` keeps identical to the originals. Credit new outside
  code in the README's "Third-party code", in `Silverbox/Licenses/` and in
  `AcknowledgmentsSheet`. Contributions come in under the MIT License, and
  the author keeps the right to use them under other licenses
  (`CONTRIBUTING.md`), so do not port GPL or other copyleft code either
  (DOSBox, 86Box, ScummVM and most emulators are GPL): the author could then
  no longer relicense. Read it to understand a format, then write our own.
- **Distribution:** Developer ID, not the App Store. App Sandbox is off,
  because the app reads libraries anywhere and starts other programs.
- **Platform versions:** Swift 6 language mode for the package and the app.
  Both require macOS 15 Sequoia. Do not use APIs from later releases without
  `if #available` (as `MenuMusicPlayer` does for macOS 27). The tests run
  only on the current macOS here, so read the availability of each new API.
- **Network:** the app's network use is the Lite game download, which
  aria2 does over BitTorrent when the user installs such a game, sharing
  nothing once the files are complete, and Sparkle's update check (once a
  day if the user agrees, sending the app's and Sparkle's versions only).
  Ask before adding any other (scraping, a crash reporter), and keep it polite: a descriptive User-Agent, a
  cache, and the service's rate limit. The website's privacy page and FAQ
  describe what the app sends; keep them in step.

## Debugging aids

- Launch arguments (debug builds): `-libraryPath "<folder>|<folder>"` (one or
  more collections), `-demoLibrary 1` (the test fixtures' eXoDOS-style and
  console libraries, with a scratch data folder in the temporary folder),
  `-dataPath <folder>` (a scratch local data folder, which also holds
  `user-library.json`, so a test install or setup never touches the real
  data; settings are not saved while either is given) and `-musicEnabled 0` and `-appearance light` (or `dark`, `system`) override saved settings for one run; `-searchText ultima` and
  `-selectTitle "Ultima V: Warriors of Destiny"` preset the view;
  `-screenshotPath out.png [-screenshotDelay 10]` renders every visible window
  (main window, then sheets as `out.2.png`, …) from the view hierarchy and
  quits; `-autoPlay 1` presses Play on the selected game after loading, which
  opens the launch options dialog; `-autoConfigure 1` opens the same dialog
  in its Configure (save only) mode; `-openWindow about` (or `help`, or
  `settings` with `-settingsTab emulators`) opens that window at start.
  `-keyPresses "right down space"` presses keys (names like `up`, `return`,
  `opt-right`, `cmd-y`) before the screenshot, to test navigation, and
  `-screenshotSettle 20` waits that many seconds after them (1.5 by
  default), for a job they start, such as Return on the install sheet;
  `-helpPage 07` opens that help page. For the site's screenshot scenes:
  `-keyPresses` works without `-screenshotPath` too, `-windowSize
  1320x840` sizes the main window, `-noLibrary 1` starts with no
  collection (the welcome), `-inspectorScroll extras` scrolls the
  inspector, and `-openInfo 1` opens the selected title's game info sheet.
  `-screenshotScroll 0.5` scrolls the Settings window (any window but the
  main one) that far down before the screenshot; 1 is the end. `-appIcon
  green` (or `amber`) sets the app icon for the run, and `-openPage 1`
  opens the selected title's game page. `-navigate "back forward up"`
  moves in the window's history after the delay (`up` is Back to
  Library); menu shortcuts do not reach the app from `-keyPresses` while
  another app is in front. A `-libraryPath` folder set up from a
  download finds the download through its setup record. If the last session closed the main
  window, macOS restores no window and the screenshot never comes; add
  `-ApplePersistenceIgnoreState YES`. Example:

  ```
  "$BUILT_PRODUCTS_DIR/Silverbox.app/Contents/MacOS/Silverbox" -libraryPath /Volumes/eXoDOS_ro -musicEnabled 0 \
      -searchText ultima -selectTitle "Ultima V: Warriors of Destiny" -screenshotPath /tmp/shot.png
  ```
- `SILVERBOX_LOG=1` prints media folder scan timings to stderr.
- `-setupPath <folder>` opens the setup sheet for an eXo download at start.
  `SILVERBOX_SETUP_TARGET=<folder> swift test --filter matchesTheWindowsSetup`
  sets up the mounted library's original archives into that folder (without
  the media add-ons, about 20 GB) and compares the result with the Windows setup,
  then installs and plans Super Tetris from it. `SILVERBOX_SETUP_REUSE=1` skips
  the unpacking when the folder already holds a setup.
  `SILVERBOX_SETUP_DOWNLOAD=<download> SILVERBOX_SETUP_TARGET=<folder> swift test
  --filter setsUpAndPlansTheDownload` does the same for any pack's download:
  it sets it up, counts games per pack and launch kind, translates every
  DOSBox config, and installs and plans the three smallest games per pack
  (with `SILVERBOX_LAUNCH_SMOKE=1`, it also starts the DOSBox ones briefly).
- `SILVERBOX_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke` starts two unpacked
  games in DOSBox Staging for a few seconds and checks the emulator log, then
  boots Windows 98 for an eXoWin9x game in DOSBox-X and one in 86Box
  (`SILVERBOX_86BOX=<executable>` when 86Box is not in /Applications).
- `SILVERBOX_DOWNLOAD_SMOKE=1 swift test --filter DownloadTests` downloads
  ZZT's Revenge (2 MB) from the mounted library's eXoDOS torrent with aria2
  into a temporary folder: a real BitTorrent download.
- Saved media indexes live in `MediaIndex/` under the local data folder;
  "Rescan Library" deletes them.
