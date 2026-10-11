# eXoMAC

eXoMAC is an emulation front-end for the Mac, built for the eXoDOS and
eXoWin9x game preservation projects. It reads an existing eXoDOS installation
(the LaunchBox XML metadata, box art, screenshots, manuals, music and videos)
in place and launches games in DOSBox Staging or DOSBox-X with a config
translated from eXoDOS's Windows launch scripts.

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

On first launch, choose your eXoDOS folder. The app never modifies the
LaunchBox files; installing a game unpacks its archive into `eXo/eXoDOS`
exactly as eXoDOS does on Windows, and favorites and play history are kept in
`~/Library/Application Support/eXoMAC`.
