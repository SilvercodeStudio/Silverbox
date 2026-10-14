# Autoexec.Mac (eXoMAC)

Welcome to Autoexec.Mac!

<img src="./eXoMAC/Assets.xcassets/AppIconAmber.imageset/autoexec-mac-amber-1024.png" width="400" alt="A.M. logo">

Autoexec.Mac is an emulation front-end for the Mac, built for the eXoDOS and
eXoWin9x game preservation projects by the eXo team (https://www.retro-exo.com).
It reads an existing eXoDOS collection (the LaunchBox XML metadata, box art,
screenshots, manuals, music and videos) in place and launches games in DOSBox
Staging or DOSBox-X with a config translated from eXoDOS's Windows launch
scripts. `eXoMAC` is the project's internal name.

The games, media and emulators are not part of this project.

## Requirements

- macOS 15 or later, on Apple silicon or Intel. 
  - Building the app from source needs Xcode 27 or higher.
- One or more eXo downloads, such as eXoDOS v6 (the full set, or Lite with
  games downloaded) and eXoWin9x. Autoexec.Mac runs their setup itself, so a
  Windows PC is not needed; a folder set up on Windows works too.
- [DOSBox Staging](https://www.dosbox-staging.org) in `/Applications`, and
  optionally [DOSBox-X](https://dosbox-x.com). Both can be located in Settings.
- For eXoWin9x: DOSBox-X, and [86Box](https://86box.net) for the thirty or so
  games that eXo runs in it.
- For console, computer and arcade platforms from a LaunchBox library:
  [RetroArch](https://www.retroarch.com) with the cores you need,
  [Dolphin](https://dolphin-emu.org) for GameCube and Wii,
  [MAME](https://www.mamedev.org) for arcade sets, or
  [Mednafen](https://mednafen.github.io). Settings › Emulators assigns one
  per platform, following the library's `Emulators.xml` by default.

## Build

Open `eXoMAC.xcodeproj` and run the "Autoexec.Mac" scheme, or use the Makefile:

```
make run                  # build with xcodebuild, then start the app
make run ARGS='-libraryPath /Volumes/eXoDOS_ro -musicEnabled 0'
make build                # build only; CONFIG=Release for a release build
make test                 # core tests (swift test)
make sweep                # translate every eXoDOS config in the mounted library
make format               # reformat the Swift sources with swift-format
make reset                # delete the app's settings and local data folder, to test a first start
```

The core library (XML parsing, media lookup, config translation, music
decoders) is a Swift package at the repo root, so `swift build` and
`swift test` work without Xcode's project. The app links the package's
`eXoCore` product as a local package dependency.

Instructions for coding agents are in `AGENTS.md`. To let Claude Code build
and read diagnostics through the open Xcode, enable MCP under Xcode ›
Settings › Intelligence, then register the server:

```
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

Xcode asks for permission when a new session connects.

## Third-party code

Two small C libraries are vendored under `Sources/`, each with its license
and a note on its origin:

- [stb_vorbis](https://github.com/nothings/stb) (public domain or MIT) decodes
  Ogg Vorbis menu music.
- [libxmp-lite](https://github.com/libxmp/libxmp) (MIT) plays MOD, S3M, XM and
  IT tracker modules.

macOS plays the other music formats itself.

On first launch, choose your eXoDOS folder. It can be read-only (an external
drive or a network share): the app never modifies it. Installed games, save
backups, edited configs, unpacked soundtracks and caches are kept in a local
data folder, by default `~/Library/Application Support/Autoexec.Mac`, which Settings
can point at another drive; favorites, play history and settings stay in
Application Support. Installing games in place inside `eXo/eXoDOS`, as eXoDOS
does on Windows, is available in Settings.

## To do

- Menu music: replace the vendored libxmp-lite with the full libxmp (without
  its depackers). That adds the two AMF variants and Epic MegaGames PSM, which
  covers ten more eXoDOS titles (Crusader, The Civil War, Jazz Jackrabbit).
  DSM (four titles) would need libmodplug as well; probably not worth it.
- Launch console, computer and arcade games for real with RetroArch, Dolphin,
  MAME and Mednafen. The planner and the emulator assignments exist; nothing
  has been played yet.
- ROM-folder collections: plain `Games/<Platform>` folders with no LaunchBox
  XML beside them, plus single titles configured by hand.
- Set up eXoDOS on the Mac: unpack a fresh download (full or Lite) without the
  Windows `Setup eXoDOS.bat`. Not started; today the app needs a finished
  install.
- Windows 9x games from eXoWin9x. The library is on the volume (the 1994-1996
  set, 648 titles) but there is no launch path yet: the `9xlaunch.bat` scripts
  and the 86Box, PCBox and DOSBox-X profiles still need translating.
- Couch mode: a full-screen, controller-first view on top of the grid and the
  controller input that exist today.
- Later: BitTorrent downloads of the eXoDOS packs, and metadata and media
  scraping for games outside the eXo collections.
