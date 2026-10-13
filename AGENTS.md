# eXoMAC

A SwiftUI front-end for the eXoDOS / eXoWin9x game preservation collections on
macOS. It reads an eXoDOS installation (LaunchBox XML, images, manuals, music,
videos, game archives) in place and launches games in DOSBox Staging or
DOSBox-X with a translated config.

The goal is a Mac client for these collections, similar to LaunchBox on
Windows: it reads the eXoDOS / LaunchBox configuration files so that an
eXoDOS installation or download is usable on the Mac. The actual emulators
(DOSBox and related) are external to this front-end project.

Names: `eXoMAC` is the internal name (project, module, folders, the local
data folder). The bundle identifier is `com.github.preston-landers.autoexec-mac`;
settings saved under the old `…eXoMAC` identifier are read until a collection
is configured.
The display name is "Autoexec.Mac"; it is set once in `AppInfo`
(`eXoMACApp.swift`) and in the `PRODUCT_NAME` and
`INFOPLIST_KEY_CFBundleDisplayName` build settings, so the built app is
`Autoexec.Mac.app`. Credit the eXo project in the About box. Do not describe
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
make reset                       # delete the app's settings and local data folder (asks first; YES=1 skips)
```

`make run` resolves the built app through `xcodebuild -showBuildSettings`,
so it shares Xcode's DerivedData.

If an Xcode MCP server is connected, use it to build, read diagnostics and
change build settings; otherwise build with `make build`. Do not edit
`project.pbxproj` by hand. New files under `eXoMAC/`, `eXoMACTests/` and
`eXoMACUITests/` are picked up automatically; files under `Sources/` and
`Tests/` belong to the package.

To check that the app sources still compile against the core without Xcode,
type-check them against the package build (see the `typecheck` target in the
Makefile).

## Conventions

- Keep core code free of Apple-only frameworks so it can later back a
  SwiftCrossUI client on Linux. Platform-specific work (unzip binary paths,
  emulator locations) stays behind small helpers with `#if os(...)`.
- Formatting. `make format` runs `swift-format` with the settings in
  `.swift-format` (4-space indent, 120 columns, sorted imports). Run it after
  changing Swift files and before the work is reviewed or committed; do not
  hand-wrap code that the formatter will rewrite.
- Dependencies. Ask before adding one. Declare package dependencies in
  `Package.swift` (remote packages pinned by `Package.resolved`, which is
  committed); dependencies of the app target alone go through Xcode's Add
  Package Dependencies, which the user does. Prefer vendoring small, stable C
  libraries over binary packages or Homebrew: each in its own target under
  `Sources/`, with the upstream `LICENSE` and a `VENDOR.md` that records the
  upstream URL, version or commit, the subset copied and any local changes.
  Never edit vendored files; put wrappers and shims in our own code (a shim
  header in `include/` is fine when it says so).
- Collections. The app loads several `LibraryCollection`s (LaunchBox-format
  libraries: eXoDOS mirrors, the console LaunchBox install) into one `Library`
  aggregate of `LibrarySnapshot`s. `Game.id` is collection-scoped
  (`<collectionID>/<launchBoxID>`) because the same GUIDs appear in several
  copies of a library; user state is keyed by `launchBoxID`. Each collection
  has path substitutions (Windows prefix to Mac folder) for relocated `Games`
  folders and drive-letter paths. Parsed libraries are cached as JSON under
  `LibraryCache/` keyed by the data files' sizes and dates; "Rescan" clears it.
- Two roots. Every library (collection folder) is read-only as far as the app is
  concerned; it may live on a read-only volume. Everything the app writes goes
  to the local data folder (`LocalStore`, default
  `~/Library/Application Support/eXoMAC/`): `Games/eXoDOS/` (unpacked games),
  `Saves/` (backups of changed files made on uninstall), `Overrides/<gameID>/`
  (edited configs), `Overlay/eXoDOS/` (writable overlay mounts for games
  unpacked inside a read-only library), `Launch/`, `Logs/`, `MediaIndex/`,
  `user-library.json`. "Install in place" (into `eXo/eXoDOS`) is an option.
- Emulators. `EmulatorKind` covers DOSBox Staging and DOSBox-X for eXoDOS
  games plus RetroArch, Dolphin, MAME and Mednafen for console, computer and
  arcade platforms (`Game.launchKind` tells them apart). Each platform's
  emulator comes from `EmulatorAssignmentResolver`: the user's choice in
  Settings, else the library's `Emulators.xml` mapped to the Mac emulators
  that are installed (`RetroArchSetup` finds cores through `retroarch.cfg`,
  with aliases for renamed cores). `RomLaunchPlanner` builds the command
  line. Never call another front-end such as OpenEmu.
- Launching: `LaunchPlanner` maps `eXo/eXoDOS` paths to the local games folder
  for locally installed games, adds overlay mounts for library-installed games
  on read-only volumes, prefers an edited config from `Overrides/`, and layers
  the global `LaunchOptions` plus per-game `LaunchOverrides` (remembered from
  the launch options dialog) on top of the translated config.
- Help pages are Markdown files in `eXoMAC/Help/` (ordered by their numeric
  prefix, title from the first `#` heading), rendered by `MarkdownHTML` in the
  Help window. Add or edit pages there.
- Navigation input. The grid and list handle arrows, Return, Space and
  Escape through SwiftUI focus (`GameGridView`, `GameListView`); media and
  page commands are menu shortcuts in `AppCommands`. `GamepadInput` turns
  controller buttons into the same key presses through `KeyPress.send`, so
  new keyboard behaviour is controller behaviour too. Help page 07 lists
  both maps; keep it in step.
- App icon. `eXoMAC/AppIcon.icon` (amber) is the Icon Composer file Xcode
  compiles into the bundle icon; `eXoMAC/AppIcon-Green.icon` is the alternate,
  compiled only when the target's "Include all app icon assets" is on. The app
  icon setting shows the chosen one in the Dock and the About window through
  `AppIconVariant.image`, which falls back to the flat 1024 px PNGs in the
  `AppIconAmber` and `AppIconGreen` image sets. The design sources (SVG masters,
  Icon Composer layers, classic PNG sets) live in `AM_icons/`.
- Reference material: a read-only eXoDOS v6 copy at `/Volumes/eXoDOS_ro`,
  LaunchBox screenshots in `Launchbox Screenshots/`, and the design prototypes
  linked from `prompt.md`.

## Debugging aids

- Launch arguments (debug builds): `-libraryPath "<folder>|<folder>"` (one or
  more collections) and `-musicEnabled 0` override saved settings for one run; `-searchText ultima` and
  `-selectTitle "Ultima V: Warriors of Destiny"` preset the view;
  `-screenshotPath out.png [-screenshotDelay 10]` renders every visible window
  (main window, then sheets as `out.2.png`, …) from the view hierarchy and
  quits; `-autoPlay 1` presses Play on the selected game after loading, which
  opens the launch options dialog; `-autoConfigure 1` opens the same dialog
  in its Configure (save only) mode; `-openWindow about` (or `help`, or
  `settings` with `-settingsTab emulators`) opens that window at start.
  `-keyPresses "right down space"` presses keys (names like `up`, `return`,
  `opt-right`, `cmd-y`) before the screenshot, to test navigation. Example:

  ```
  "$BUILT_PRODUCTS_DIR/Autoexec.Mac.app/Contents/MacOS/Autoexec.Mac" -libraryPath /Volumes/eXoDOS_ro -musicEnabled 0 \
      -searchText ultima -selectTitle "Ultima V: Warriors of Destiny" -screenshotPath /tmp/shot.png
  ```
- `EXOMAC_LOG=1` prints media folder scan timings to stderr.
- `EXOMAC_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke` starts two unpacked
  games in DOSBox Staging for a few seconds and checks the emulator log.
- Saved media indexes live in `~/Library/Application Support/eXoMAC/MediaIndex`;
  "Rescan Library" deletes them.
