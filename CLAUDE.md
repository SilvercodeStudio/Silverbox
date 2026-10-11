# eXoMAC

A SwiftUI front-end for the eXoDOS / eXoWin9x game preservation collections on
macOS. It reads an eXoDOS installation (LaunchBox XML, images, manuals, music,
videos, game archives) in place and launches games in DOSBox Staging or
DOSBox-X with a translated config. See `AGENTS.md` for the project goal.

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
swift build                      # core only
swift test                       # core tests (fast; real-library tests if mounted)
xcodebuild -project eXoMAC.xcodeproj -scheme eXoMAC -destination 'platform=macOS' build
```

The Xcode MCP server is available; use it to build, read diagnostics and change
build settings. Do not edit `project.pbxproj` by hand. New files under
`eXoMAC/`, `eXoMACTests/` and `eXoMACUITests/` are picked up automatically.

## Conventions

- Keep core code free of Apple-only frameworks so it can later back a
  SwiftCrossUI client on Linux. Platform-specific work (unzip binary paths,
  emulator locations) stays behind small helpers with `#if os(...)`.
- The app never writes to the eXoDOS folder except when installing or
  uninstalling a game (unpacking `eXo/eXoDOS/<name>.zip`). User changes such as
  favorites and play history live in `~/Library/Application Support/eXoMAC/`.
- Generated DOSBox configs go to `~/Library/Application Support/eXoMAC/Launch/`
  and emulator output to `.../Logs/`.
- Reference material: a read-only eXoDOS v6 copy at `/Volumes/eXoDOS_ro`,
  LaunchBox screenshots in `Launchbox Screenshots/`, and the design prototypes
  linked from `prompt.md`.

## Debugging aids

- Launch arguments (debug builds): `-libraryPath <folder>` and `-musicEnabled 0`
  override saved settings for one run; `-searchText ultima` and
  `-selectTitle "Ultima V: Warriors of Destiny"` preset the view;
  `-screenshotPath out.png [-screenshotDelay 10]` renders the main window to a
  PNG from the view hierarchy and quits. Example:

  ```
  "$BUILT_PRODUCTS_DIR/eXoMAC.app/Contents/MacOS/eXoMAC" -libraryPath /Volumes/eXoDOS_ro -musicEnabled 0 \
      -searchText ultima -selectTitle "Ultima V: Warriors of Destiny" -screenshotPath /tmp/shot.png
  ```
- `EXOMAC_LOG=1` prints media folder scan timings to stderr.
- `EXOMAC_LAUNCH_SMOKE=1 swift test --filter LaunchSmoke` starts two unpacked
  games in DOSBox Staging for a few seconds and checks the emulator log.
- Saved media indexes live in `~/Library/Application Support/eXoMAC/MediaIndex`;
  "Rescan Library" deletes them.
