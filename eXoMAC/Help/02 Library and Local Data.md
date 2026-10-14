# Collections and the local data folder

Autoexec.Mac reads from one or more collections and writes only to a local data folder.

## Collections

A collection is an eXoDOS or eXoWin9x install, or any LaunchBox library folder: the folder that holds `Data` and `Images`, and for eXoDOS also `eXo`, `Manuals`, `Music` and `Videos`. A collection can live on an external drive or a network share, and it can be read-only. Autoexec.Mac only reads from it: game metadata, artwork, manuals, music, videos, game archives, DOSBox configurations and the MT-32 sound files.

Each collection appears as its own section in the sidebar. All Games, Favorites, Installed, Recently Played and search span every collection.

Add collections on first launch, in Settings › Library, or by dropping the folder onto the window from the Finder. If a library's game files live elsewhere than its metadata, for example a `Games` folder copied to a NAS or paths on a Windows drive letter, add a path substitution to the collection: a Windows prefix mapped to a folder on this Mac.

## The local data folder

Everything bulky that Autoexec.Mac writes goes to one folder. By default it is `~/Library/Application Support/Autoexec.Mac`; Settings › Library can point it at another folder, for example on an external drive. Choosing a drive or your home folder puts an `Autoexec.Mac` folder there; Use Default goes back to the standard location. What is already in the old folder is not moved. The folder holds:

- `Games` — games you have installed (unpacked from their archives).
- `Soundtracks` — albums unpacked from the library's soundtrack zips.
- `Saves` — backups of saved games and changed settings, made when you uninstall a game.
- `Overrides` — your edited copies of DOSBox configurations.
- `Overlay` — writable folders and disk copies for games that are already unpacked inside a read-only library, and the Windows 98 disks that eXoWin9x games write to.
- `Launch` and `Logs` — the configurations Autoexec.Mac generates for each launch, and the emulator's output.
- `MediaIndex` and `LibraryCache` — caches that Rescan Library rebuilds.

Favorites, play history and the settings stay in `~/Library/Application Support/Autoexec.Mac` on this Mac, so they are there even when the drive is not. If the chosen folder is missing when the app starts, it says so; installed games and caches on it wait until the drive is back.

## Installing in place

If your eXoDOS folder is writable and you prefer the Windows layout, set Settings › Library › "Install games to" to the eXoDOS folder. Games then unpack into `eXo/eXoDOS` (eXoWin9x games into `eXo/eXoWin9x/<year>`), where LaunchBox on Windows would also find them.

## Rescanning

After you add or update eXoDOS packs, choose Library › Rescan Library. This re-reads the metadata and rebuilds the artwork index.
