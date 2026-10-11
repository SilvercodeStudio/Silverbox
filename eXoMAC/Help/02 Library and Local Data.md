# Collections and the local data folder

eXo Client reads from one or more collections and writes only to a local data folder.

## Collections

A collection is an eXoDOS or eXoWin9x install, or any LaunchBox library folder: the folder that holds `Data` and `Images`, and for eXoDOS also `eXo`, `Manuals`, `Music` and `Videos`. A collection can live on an external drive or a network share, and it can be read-only. eXo Client only reads from it: game metadata, artwork, manuals, music, videos, game archives, DOSBox configurations and the MT-32 sound files.

Each collection appears as its own section in the sidebar. All Games, Favorites, Installed, Recently Played and search span every collection.

Add collections on first launch or in Settings › Library. If a library's game files live elsewhere than its metadata, for example a `Games` folder copied to a NAS or paths on a Windows drive letter, add a path substitution to the collection: a Windows prefix mapped to a folder on this Mac.

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
