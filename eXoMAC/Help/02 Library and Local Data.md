# The library and the local data folder

eXo Client works with two folders.

## The eXoDOS folder (the library)

This is the collection itself: the folder that holds `eXo`, `Data`, `Images`, `Manuals`, `Music` and `Videos`. It can live on an external drive or a network share, and it can be read-only. eXo Client only reads from it: game metadata, artwork, manuals, music, videos, game archives, DOSBox configurations and the MT-32 sound files.

Choose it on first launch, or later in Settings › Library.

## The local data folder

Everything eXo Client writes goes to a folder on your Mac. By default it is `~/Library/Application Support/eXoMAC`; you can choose another location in Settings › Library. It holds:

- `Games` — games you have installed (unpacked from their archives).
- `Saves` — backups of saved games and changed settings, made when you uninstall a game.
- `Overrides` — your edited copies of DOSBox configurations.
- `Overlay` — writable folders for games that are already unpacked inside a read-only library.
- `Launch` and `Logs` — the configurations eXo Client generates for each launch, and the emulator's output.
- `MediaIndex` and `user-library.json` — caches, favorites and play history.

## Installing in place

If your eXoDOS folder is writable and you prefer the Windows layout, set Settings › Library › "Install games to" to the eXoDOS folder. Games then unpack into `eXo/eXoDOS`, where LaunchBox on Windows would also find them.

## Rescanning

After you add or update eXoDOS packs, choose Library › Rescan Library. This re-reads the metadata and rebuilds the artwork index.
