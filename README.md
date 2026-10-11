# eXo Client for Mac (eXoMAC)

eXo Client is an emulation front-end for the Mac, built for the eXoDOS and
eXoWin9x game preservation projects by the eXo team (https://www.retro-exo.com).
It reads an existing eXoDOS collection (the LaunchBox XML metadata, box art,
screenshots, manuals, music and videos) in place and launches games in DOSBox
Staging or DOSBox-X with a config translated from eXoDOS's Windows launch
scripts. `eXoMAC` is the project's internal name.

The games, media and emulators are not part of this project.

## Requirements

- macOS 27 and Xcode 27.
- An eXoDOS v6 installation (the full set, or Lite with games downloaded).
- [DOSBox Staging](https://www.dosbox-staging.org) in `/Applications`, and
  optionally [DOSBox-X](https://dosbox-x.com). Both can be located in Settings.

## Build

Open `eXoMAC.xcodeproj` and run the `eXoMAC` scheme, or:

```
xcodebuild -project eXoMAC.xcodeproj -scheme eXoMAC -destination 'platform=macOS' build
```

The core library (XML parsing, media lookup, config translation) is a plain
Swift package at the repo root:

```
swift test
```

On first launch, choose your eXoDOS folder. It can be read-only (an external
drive or a network share): the app never modifies it. Installed games, save
backups, edited configs, favorites and play history are kept in a local data
folder, by default `~/Library/Application Support/eXoMAC`. Installing games in
place inside `eXo/eXoDOS`, as eXoDOS does on Windows, is available in Settings.
