# Collections and the local data folder

Autoexec.Mac reads from one or more collections and writes only to a local data folder.

## Collections

A collection is an eXoDOS or eXoWin9x install, or any LaunchBox library folder: the folder that holds `Data` and `Images`, and for eXoDOS also `eXo`, `Manuals`, `Music` and `Videos`. A collection can live on an external drive or a network share, and it can be read-only. Autoexec.Mac only reads from it: game metadata, artwork, manuals, music, videos, game archives, DOSBox configurations and the MT-32 sound files.

Each collection appears as its own section in the sidebar. All Games, Favorites, Installed, Recently Played and search span every collection. When you have more than one eXo pack (for example eXoDOS and eXoScummVM), the eXo Packs section shows the games of each pack on its own, even when several packs share one collection; the game's details also name its pack.

Add collections on first launch, in Settings › Library, or by dropping the folder onto the window from the Finder. A folder set up on Windows, or one you set up here, can be added as it is. If a library's game files live elsewhere than its metadata, for example a `Games` folder copied to a NAS or paths on a Windows drive letter, add a path substitution to the collection: a Windows prefix mapped to a folder on this Mac.

## Setting up an eXo download

An eXo download, as the torrent delivers it, holds a `Content` folder of archives and a setup script for Windows. Add the download folder, and Autoexec.Mac offers to set it up. Setup does what eXo's script does on Windows: it unpacks the game lists, box art, launch settings, media add-ons and emulator files, and builds the `Data` folder. The game archives stay packed until you install a game.

To merge packs, as eXo does, copy them into one folder first, keeping their folder layout. Setup finds every pack in the folder and sets them up together. If you add a pack to a folder that is already set up, add the folder again and setup runs once more for all packs.

Setup asks:

- **Include adult games** — eXo marks some games as adult because of nudity. Left out, they stay on disk but are not listed.
- **Manuals, music and extras** (eXoDOS) — each game's extras come in a zip of their own, 120 GB in all. Unpack them all now, or unpack each game's when you install it.
- **Media add-ons** — books, catalogs, magazines, soundtracks and videos are large. Leave out any you do not want.

Setup can write into the download folder, as on Windows, or into `Collections` in the local data folder, which leaves the download as it came; the game archives are then still read from the download. If the download cannot be written, for example on a read-only network share, setup always writes to the local data folder. Adding the download again later finds the earlier setup in either place. Setup needs about as much free space as the archives it unpacks; the sheet shows the space needed and the space free. Display choices from eXo's setup are left out: the launch options take their place.

## The local data folder

Everything bulky that Autoexec.Mac writes goes to one folder. By default it is `~/Library/Application Support/Autoexec.Mac`; Settings › Library can point it at another folder, for example on an external drive. Choosing a drive or your home folder puts an `Autoexec.Mac` folder there; Use Default goes back to the standard location. What is already in the old folder is not moved. The folder holds:

- `Games` — games you have installed (unpacked from their archives).
- `Soundtracks` — albums unpacked from the library's soundtrack zips.
- `Saves` — backups of saved games and changed settings, made when you uninstall a game.
- `Overrides` — your edited copies of DOSBox configurations.
- `Collections` — downloads set up here because their own folder is read-only.
- `Overlay` — writable folders and disk copies for games that are already unpacked inside a read-only library, and the Windows 98 disks that eXoWin9x games write to.
- `Launch` and `Logs` — the configurations Autoexec.Mac generates for each launch, and the emulator's output.
- `MediaIndex` and `LibraryCache` — caches that Rescan Library rebuilds.

Favorites, play history and the settings stay in `~/Library/Application Support/Autoexec.Mac` on this Mac, so they are there even when the drive is not. If the chosen folder is missing when the app starts, it says so; installed games and caches on it wait until the drive is back.

## Installing in place

If your eXoDOS folder is writable and you prefer the Windows layout, set Settings › Library › "Install games to" to the eXoDOS folder. Games then unpack into `eXo/eXoDOS` (eXoWin9x games into `eXo/eXoWin9x/<year>`), where LaunchBox on Windows would also find them.

## Rescanning

After you add or update eXoDOS packs, choose Library › Rescan Library. This re-reads the metadata and rebuilds the artwork index.
