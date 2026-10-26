# Silverbox

A SwiftUI front-end for the eXoDOS / eXoWin9x game preservation collections on
macOS. It reads an eXoDOS installation (LaunchBox XML, images, manuals, music,
videos, game archives) in place and launches games in DOSBox Staging or
DOSBox-X with a translated config.

The goal is a Mac client for these collections, similar to LaunchBox on
Windows: it reads the eXoDOS / LaunchBox configuration files so that an
eXoDOS installation or download is usable on the Mac. The actual emulators
(DOSBox and related) are external to this front-end project.

Names: the project, module and folders use the internal name `eXoMAC`. The local
data folder is `~/Library/Application Support/Silverbox`. The bundle
identifier is `app.getsilverbox.Silverbox`.
The display name is "Silverbox"; it is set once in `AppInfo`
(`eXoMACApp.swift`) and in the `PRODUCT_NAME` and
`INFOPLIST_KEY_CFBundleDisplayName` build settings, so the built app is
`Silverbox.app`. Credit the eXo project in the About box. Do not describe
the app as a collection of classic Mac games.

## Layout

- `Sources/eXoCore/` — the portable core: Foundation only, no AppKit/SwiftUI.
  LaunchBox XML parsing, library snapshot and queries, media lookup, DOSBox
  config translation, launch planning, installing, user state, music
  decoders. Every type here is marked `nonisolated` because the app target
  uses MainActor as the default isolation; the package build enforces the
  same rule. Anything the app uses must be `public`.
- `Sources/CStbVorbis/`, `Sources/CXmpLite/` — vendored C decoders (Ogg
  Vorbis; MOD/S3M/XM/IT modules), each its own package target with the
  upstream `LICENSE` and a `VENDOR.md` note.
- `eXoMAC/App/`, `eXoMAC/Views/`, `eXoMAC/Services/` — the Mac app. Every
  file imports `eXoCore`.
- `Tests/eXoCoreTests/` — Swift Testing suites for the core, with a small
  LaunchBox-style library and audio samples under `Fixtures/`. Tests in
  `RealLibraryTests.swift` run only when `/Volumes/eXoDOS_ro` (or
  `$EXOMAC_TEST_LIBRARY`) exists.
- `Package.swift` at the repo root defines the `eXoCore` library and the
  vendored C targets. The Xcode app target links the `eXoCore` product as a
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
make lint                        # report formatting problems without changing files
make install-app                 # universal Release build copied to ~/Applications (APP_DIR=... elsewhere)
make reset                       # delete the app's settings and local data folder (asks first; YES=1 skips)
```

`make run` resolves the built app through `xcodebuild -showBuildSettings`,
so it shares Xcode's DerivedData.

If an Xcode MCP server is connected, use it to build, read diagnostics and
change build settings; otherwise build with `make build`. Do not edit
`project.pbxproj` by hand. New files under `eXoMAC/` are picked up
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
- Two roots. Every library (collection folder) is read-only as far as the app is
  concerned; it may live on a read-only volume. Everything bulky the app writes
  goes to the local data folder (`LocalStore` plus `AppPaths.dataRoot`, default
  `~/Library/Application Support/Silverbox/`, movable to another drive in
  Settings; `user-library.json` and the settings always stay in Application
  Support): `Games/` (unpacked games; mirrors `eXo/`, so `Games/eXoDOS/<folder>`
  and `Games/eXoWin9x/<year>/<folder>`),
  `Saves/` (backups of changed files made on uninstall), `Overrides/<gameID>/`
  (edited configs), `Overlay/` (also mirrors `eXo/`: `eXoDOS/` overlay mounts
  for games unpacked inside a read-only library, copies of eXoWin9x game disks,
  and the Windows 98 differencing disks under `emulators/`), `Soundtracks/`
  (albums unpacked from the library's zips), `Launch/`, `Logs/`, `MediaIndex/`,
  `user-library.json`. "Install in place" (into `eXo/eXoDOS`) is an option.
- Emulators. `EmulatorKind` covers DOSBox Staging and DOSBox-X for eXoDOS
  games, 86Box (`.box86`) for some eXoWin9x games, plus RetroArch, Dolphin, MAME and Mednafen for console, computer and
  arcade platforms (`Game.launchKind` tells them apart). Each platform's
  emulator comes from `EmulatorAssignmentResolver`: the user's choice in
  Settings, else the library's `Emulators.xml` mapped to the Mac emulators
  that are installed (`RetroArchSetup` finds cores through `retroarch.cfg`,
  with aliases for renamed cores). `RomLaunchPlanner` builds the command
  line. Never call another front-end such as OpenEmu.
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
  and `dosboxIndex(for:)`. eXoAppleIIGS games install but do not launch yet. Each pack's `Setup <pack>.bat` entry is hidden
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
  `Collections/<name>` in the local data folder with
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
  atari800 gets eXo's Altirra ROMs in its own system folder through
  `--appendconfig`; PUAE needs a Kickstart in RetroArch's system folder),
  everything else is `unsupported` (`LaunchVariant.unsupportedReason`, which
  also names a missing core or ROM). The app's `launchPlanner(_:)` passes
  `settings.retroArchSetup`. The default version is the best `preference`:
  Spatterlight, then DOS, then RetroArch.
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
  launcher name first, then title.
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
- Background jobs. `InstallRun` (observable) drives one installation:
  `AppModel.startInstall` runs `GameInstaller.install` with its progress
  closure, `JobsBar` shows the runs above the now-playing bar, Cancel stops
  the unzip and removes the half-made folder, `DockProgress` draws the mean
  progress on the Dock tile, and `JobNotifier` bounces and notifies when a
  job finishes while the app is in the background. Setup reports through
  the same two services.
- Sidebar. Rows carry `.badge` counts from `AppModel.sidebarCounts`,
  recounted off the main thread shortly after the library or the user's
  state changes (playlists are not counted); each collection's header shows
  its game count and "read-only", and `DataFolderFooter` shows the local
  data folder. Empty states use `ContentUnavailableView`.
- List view. Column headers for Title, Year and Developer sort through
  `settings.sortOrder` and `settings.sortAscending`, the same settings as
  the toolbar's Sort menu; `Game.sortYear` and `sortDeveloper` give
  `KeyPathComparator` non-optional keys.
- About. `AboutView` opens `AcknowledgmentsSheet` and `LicenseSheet`; the
  texts come from `eXoMAC/Licenses/*.txt`, copies of the repository's
  `LICENSE` and the vendored decoders' licenses that `ProjectFilesTests`
  keeps identical. The license is MIT; the name and icon artwork are not.
- Status chips. `Chip` and `ChipRow` (`Chips.swift`) state one fact each in
  a tone: `Theme.good`, `.warning` or `.bad`, kept apart from the accent.
  Use these tones for status, never `.red` or `.orange`. `GameStatusChips`
  in the inspector header says whether the game is installed, which
  emulator runs it and whether that emulator is present. Keep chip text to
  a few words and put the whole reason in its `help`; a control that is
  disabled says why in `.help` too.
- Emulator status. `AppModel.checkEmulators()` records what is installed
  (`EmulatorCheck`) at start, when the app comes to the front and every two
  seconds while Settings › Emulators or `WelcomeView` is open
  (`.watchingForEmulators()`). Views ask `model.emulatorInstallation(_:)`,
  `model.retroArchSetup` or `emulatorResolver()`, which read the check, not
  `settings.emulatorInstallation(_:)`, so they redraw when it changes.
- First start. With no collection, the content column shows `WelcomeView`:
  Add Collection (`addFolder` takes an eXo download or a set-up
  collection) and the emulators each pack needs.
- Launching: `LaunchPlanner` maps `eXo/eXoDOS` paths to the local games folder
  for locally installed games, adds overlay mounts for library-installed games
  on read-only volumes, prefers an edited config from `Overrides/`, and layers
  the global `LaunchOptions` plus per-game `LaunchOverrides` (remembered from
  the launch options dialog) on top of the translated config.
- Help pages are Markdown files in `eXoMAC/Help/` (ordered by their numeric
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
  Keyboard Shortcuts window) and help page 07. Context menus are AppKit
  menus and do not change once open, so anything loaded for them (the Extras
  submenu) comes from `AppModel.extrasCache`, filled on hover and selection.
- App icon. A floppy disk: `eXoMAC/AppIcon.icon` (amber) is the Icon
  Composer file Xcode compiles into the bundle icon;
  `eXoMAC/AppIcon-Green.icon` is the alternate, compiled only when the
  target's "Include all app icon assets" is on. The app icon setting shows
  the chosen one in the Dock and the About window through
  `AppIconVariant.image`, which falls back to the flat 1024 px PNGs in the
  `AppIconAmber` and `AppIconGreen` image sets. Icon Composer's `ictool
  --export-image` makes them; make them again when an icon changes. A
  Dock icon set at run time is a flat image, so only the bundle icon
  (amber) follows the system's icon style (dark, clear, tinted). The
  chosen icon also sets the accent: `Theme.accent` and `Theme.accentText`
  read `ThemeAccent.shared` (observable, set by `AppModel.applyAppIcon`), and each scene applies
  `.tint(Theme.accent)` for controls. Use `Theme.accent`, not
  `Color.accentColor` (the asset catalog's fixed amber). Every `Theme`
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
- **Not yet verified:** launches of console, computer and arcade games
  (RetroArch, Dolphin, MAME, Mednafen), eXoIF's RetroArch versions, and
  eXoDOS Lite downloads. Say so when a change touches
  these, and do not describe them as working in the README or the help.
- The real-library tests check values read from eXo's own files. Do not
  change them to make a test pass.

## Constraints

- **Dependencies:** ask before adding one. Today there are none outside the
  two vendored C decoders. Declare package dependencies in `Package.swift`
  (remote packages pinned by `Package.resolved`, which is committed);
  dependencies of the app target alone go through Xcode's Add Package
  Dependencies, which the user does. Prefer vendoring small, stable C
  libraries over binary packages or Homebrew: each in its own target under
  `Sources/`, with the upstream `LICENSE` and a `VENDOR.md` that records the
  upstream URL, version or commit, the subset copied and any local changes.
  Never edit vendored files; put wrappers and shims in our own code (a shim
  header in `include/` is fine when it says so). Emulators and `unzip`/`bsdtar`
  are external programs, never linked.
- **Licensing:** the code is under the MIT License (`LICENSE`); the name and
  the icon artwork are excluded from it. The app shows it and the vendored
  licenses from `eXoMAC/Licenses/`, which `ProjectFilesTests` keeps identical
  to the originals. Credit new outside code in the README's "Third-party
  code", in `eXoMAC/Licenses/` and in `AcknowledgmentsSheet`. Do not port GPL
  code (DOSBox, 86Box, ScummVM and most emulators are GPL): read it to
  understand a format, then write our own.
- **Distribution:** Developer ID, not the App Store. App Sandbox is off,
  because the app reads libraries anywhere and starts other programs.
- **Platform versions:** Swift 6 language mode for the package and the app.
  Both require macOS 15 Sequoia. Do not use APIs from later releases without
  `if #available` (as `MenuMusicPlayer` does for macOS 27). The tests run
  only on the current macOS here, so read the availability of each new API.
- **Network:** the app makes no network requests. Ask before adding any (an
  update check, downloads for eXoDOS Lite, scraping), and keep them polite:
  a descriptive User-Agent, a cache, and the service's rate limit.

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
  `opt-right`, `cmd-y`) before the screenshot, to test navigation;
  `-helpPage 07` opens that help page. If the last session closed the main
  window, macOS restores no window and the screenshot never comes; add
  `-ApplePersistenceIgnoreState YES`. Example:

  ```
  "$BUILT_PRODUCTS_DIR/Silverbox.app/Contents/MacOS/Silverbox" -libraryPath /Volumes/eXoDOS_ro -musicEnabled 0 \
      -searchText ultima -selectTitle "Ultima V: Warriors of Destiny" -screenshotPath /tmp/shot.png
  ```
- `EXOMAC_LOG=1` prints media folder scan timings to stderr.
- `-setupPath <folder>` opens the setup sheet for an eXo download at start.
  `EXOMAC_SETUP_TARGET=<folder> swift test --filter matchesTheWindowsSetup`
  sets up the mounted library's original archives into that folder (without
  the media add-ons, about 20 GB) and compares the result with the Windows setup,
  then installs and plans Super Tetris from it. `EXOMAC_SETUP_REUSE=1` skips
  the unpacking when the folder already holds a setup.
  `EXOMAC_SETUP_DOWNLOAD=<download> EXOMAC_SETUP_TARGET=<folder> swift test
  --filter setsUpAndPlansTheDownload` does the same for any pack's download:
  it sets it up, counts games per pack and launch kind, translates every
  DOSBox config, and installs and plans the three smallest games per pack
  (with `EXOMAC_LAUNCH_SMOKE=1`, it also starts the DOSBox ones briefly).
- `EXOMAC_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke` starts two unpacked
  games in DOSBox Staging for a few seconds and checks the emulator log, then
  boots Windows 98 for an eXoWin9x game in DOSBox-X and one in 86Box
  (`EXOMAC_86BOX=<executable>` when 86Box is not in /Applications).
- Saved media indexes live in `MediaIndex/` under the local data folder;
  "Rescan Library" deletes them.
