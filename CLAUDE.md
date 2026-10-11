# eXoMAC

A SwiftUI front-end for the eXoDOS / eXoWin9x game preservation collections on
macOS. It reads an eXoDOS installation (LaunchBox XML, images, manuals, music,
videos, game archives) in place and launches games in DOSBox Staging or
DOSBox-X with a translated config. See `AGENTS.md` for the project goal.

Names: `eXoMAC` is the internal name (project, module, bundle id, folders).
The display name is "eXo Client" ("eXo Client for Mac" in the About box); it is
set once in `AppInfo` (`eXoMACApp.swift`) and in the `PRODUCT_NAME` and
`INFOPLIST_KEY_CFBundleDisplayName` build settings, so the built app is
`eXo Client.app`. Do not describe the app as a collection of classic Mac games.

## Layout

- `eXoMAC/Core/` — the portable core: Foundation only, no AppKit/SwiftUI.
  LaunchBox XML parsing, library snapshot and queries, media lookup, DOSBox
  config translation, launch planning, installing, user state. Every type here
  is marked `nonisolated` because the app target uses MainActor as the default
  isolation; the package build enforces the same rule.
- `eXoMAC/App/`, `eXoMAC/Views/`, `eXoMAC/Services/` — the Mac app.
- `Tests/eXoCoreTests/` — Swift Testing suites for the core, with a small
  LaunchBox-style library under `Fixtures/`. Tests in `RealLibraryTests.swift`
  run only when `/Volumes/eXoDOS_ro` (or `$EXOMAC_TEST_LIBRARY`) exists.
- `Package.swift` at the repo root builds `eXoMAC/Core` as the `eXoCore`
  module. The Xcode app target compiles the same files through its
  folder-synchronized group, so the app does not link the package.

## Build and test

```
make run [ARGS='...']            # xcodebuild the app, then start it in the foreground
make build                       # app only (CONFIG=Release for a release build)
make test                        # swift test: core tests (fast; real-library tests if mounted)
make core                        # swift build: core only
```

`make run` resolves the built app through `xcodebuild -showBuildSettings`,
so it shares Xcode's DerivedData.

The Xcode MCP server is available; use it to build, read diagnostics and change
build settings. Do not edit `project.pbxproj` by hand. New files under
`eXoMAC/`, `eXoMACTests/` and `eXoMACUITests/` are picked up automatically.

## Conventions

- Keep core code free of Apple-only frameworks so it can later back a
  SwiftCrossUI client on Linux. Platform-specific work (unzip binary paths,
  emulator locations) stays behind small helpers with `#if os(...)`.
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
- Launching: `LaunchPlanner` maps `eXo/eXoDOS` paths to the local games folder
  for locally installed games, adds overlay mounts for library-installed games
  on read-only volumes, prefers an edited config from `Overrides/`, and layers
  the global `LaunchOptions` plus per-game `LaunchOverrides` (remembered from
  the launch options dialog) on top of the translated config.
- Help pages are Markdown files in `eXoMAC/Help/` (ordered by their numeric
  prefix, title from the first `#` heading), rendered by `MarkdownHTML` in the
  Help window. Add or edit pages there.
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
  in its Configure (save only) mode. Example:

  ```
  "$BUILT_PRODUCTS_DIR/eXo Client.app/Contents/MacOS/eXo Client" -libraryPath /Volumes/eXoDOS_ro -musicEnabled 0 \
      -searchText ultima -selectTitle "Ultima V: Warriors of Destiny" -screenshotPath /tmp/shot.png
  ```
- `EXOMAC_LOG=1` prints media folder scan timings to stderr.
- `EXOMAC_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke` starts two unpacked
  games in DOSBox Staging for a few seconds and checks the emulator log.
- Saved media indexes live in `~/Library/Application Support/eXoMAC/MediaIndex`;
  "Rescan Library" deletes them.
