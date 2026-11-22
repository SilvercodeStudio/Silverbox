# Collections and the local data folder

Silverbox reads from one or more collections and writes to a separate local data folder. It doesn't change your eXo download unless you ask it to, by setting the download up in place or installing games in place.

## Collections

A collection is a set-up eXo pack (or several packs merged into one folder), or any LaunchBox library folder. It's the folder that holds `Data` and `Images`, plus `eXo`, `Manuals`, `Music` and `Videos` for the eXo packs. A collection can live on an external drive or a network share, and it can be read-only: Silverbox only reads from it.

Each collection gets its own section in the sidebar, with a count of its titles: the games, along with any books, magazines, soundtracks and videos. The rows under eXo Packs count games only. Playlist names are shortened to save space ("MT-32" instead of "eXoDOS Games with MT-32"); hover over one to see the full name. All Games, Favorites, Installed and Recently Played cover every collection.

Search looks in the selected section and puts the closest title matches first, so "Ultima" finds the Ultima games before "Ultimate Soccer Manager".

Favorites holds the games you mark with the heart (Command-D). Each copy of a game is tracked separately, so favoriting the eXoIF copy of a game doesn't touch its eXoDOS copy. The eXo team also picks recommended games in each pack; those are under **eXo Favorites**, separate from yours, and the game's details say "an eXo Favorite". In other LaunchBox libraries, the favorites you saved in LaunchBox count as yours. When you have more than one eXo pack (say, eXoDOS and eXoScummVM), the eXo Packs section lists each pack separately, even when several packs share one collection.

The same game is often in several packs or collections: many Infocom games are in eXoDOS, eXoScummVM and eXoIF, and some eXoDOS games also have a CD-ROM or Windows 95 release. **Other Versions** in a game's context menu lists them, with the pack or platform of each, and choosing one jumps straight to it. Games count as versions of each other when their titles match and they share a developer or publisher, so two different games that happen to share a title, such as Deadline, stay apart.

Add a collection with Add Collection… on the welcome screen or in Settings › Library, or drop the folder onto the window from the Finder. Don't worry about picking exactly the right folder: if you choose one inside a collection, such as `eXo` or `Data`, or the folder that contains it, Silverbox finds the collection. A folder set up on Windows works as is. Settings › Library lists each collection with what was found in it, and lets you rename it, turn it off or choose its folder again. If a collection's folder is missing, it says so; choose the folder again if you moved or renamed it. If a library's game files live elsewhere than its metadata, for example a `Games` folder copied to a NAS or paths on a Windows drive letter, add a path substitution to the collection: a Windows prefix mapped to a folder on this Mac.

## Setting up an eXo download

An eXo download, as the torrent delivers it, holds a `Content` folder of archives and a setup script for Windows. Add the download folder, and Silverbox offers to set it up. Setup does what eXo's script does on Windows: it unpacks the game lists, box art, launch settings, media add-ons and emulator files, and builds the `Data` folder. The game archives stay packed until you install a game.

To merge packs, as eXo does, copy them into one folder first, keeping their folder layout. Setup finds every pack in the folder and sets them up together. If you add a pack to a folder that is already set up, add the folder again and setup runs once more for all packs.

Setup asks:

- **Include adult games** — eXo marks some games as adult because of nudity. Left out, they stay on disk but are not listed.
- **Manuals, music and extras** (eXoDOS) — each game's extras come in a zip of their own, 120 GB in all. Unpack them all now, or unpack each game's when you install it.
- **Media add-ons** — books, catalogs, magazines, soundtracks and videos are large. Leave out any you do not want.

Setup can write into the download folder, as on Windows, or into `Collections` in the local data folder, which leaves your download untouched (the game archives are still read from it). If the download can't be written to, for example on a read-only network share, setup always uses the local data folder. Adding the same download again later finds the earlier setup either way. Setup needs about as much free space as the archives it unpacks, and the sheet shows how much you need and how much you have. eXo's display questions are left out of setup; the launch options cover them instead.

## eXoDOS Lite: downloading games

The eXoDOS Lite download leaves out every game archive and its manuals, music and extras, and includes the full collection's torrent in `eXo/util/aria`. When you install a game that the collection lacks, the install sheet shows its download size, and Download and Install fetches it from that torrent, as eXo's script does on Windows. A full collection with some archives deleted works the same way.

Downloads need [aria2](https://aria2.github.io/), a free download program: install it with Homebrew (`brew install aria2`). Settings › Library › Game downloads says whether it is found. Silverbox starts aria2 for each game, one game at a time, and aria2 stops sharing as soon as the files are complete. The first download can wait a minute or so at "Looking for peers" while aria2 finds other computers sharing the torrent. aria2 then keeps a list of them, so later downloads start in seconds. As with any BitTorrent program, the other computers in the swarm see your IP address.

The archives go into the set-up collection, as on Windows. If you set up in place, that's your download folder; otherwise it's Silverbox's own copy in `Collections`, and your download is left alone. A collection that was set up on Windows and sits on a read-only drive or share can't download games. The game's zip goes into `eXo/eXoDOS`. Its manuals, music and extras go into `Content/GameData/eXoDOS` and are then unpacked into the collection. Unfinished downloads wait in `eXo/DOWNLOAD`; Cancel stops a download, and installing the game again resumes it. A game that eXo added after the torrent was made is not in it; it comes with the update that added it.

## The local data folder

Everything bulky that Silverbox writes goes to one folder. By default it's `~/Library/Application Support/Silverbox`, but Settings › Library can move it elsewhere, for example to an external drive. If you choose a drive or your home folder, Silverbox makes a `Silverbox` folder there. Changing the folder doesn't move what's already in the old one. If you move or rename the folder in the Finder, choose it again in Settings: the collections set up in its `Collections` folder follow it. The folder holds:

- `Games` — games you have installed (unpacked from their archives).
- `Soundtracks` — albums unpacked from the library's soundtrack zips.
- `Saves` — backups of saved games and changed settings, made when you uninstall a game.
- `Overrides` — your edited copies of DOSBox configurations.
- `Collections` — downloads set up here because their own folder is read-only.
- `Overlay` — writable folders and disk copies for games that are already unpacked inside a read-only library, and the Windows 98 disks that eXoWin9x games write to.
- `Launch` and `Logs` — the configurations Silverbox generates for each launch, and the emulator's output.
- `MediaIndex` and `LibraryCache` — caches that Rescan Library rebuilds.
- `BitTorrent` — aria2's list of peers to ask, which lets the next game download start sooner.

Favorites, play history and the settings stay in `~/Library/Application Support/Silverbox` on this Mac, so they are there even when the drive is not. If the chosen folder is missing when the app starts, it says so; installed games and caches on it wait until the drive is back.

## Installing in place

If your eXoDOS folder is writable and you prefer the Windows layout, set Settings › Library › "Install games to" to "Inside the eXoDOS folder, as on Windows". Games then unpack into `eXo/eXoDOS` (eXoWin9x games into `eXo/eXoWin9x/<year>`), where LaunchBox on Windows would also find them.

## Rescanning

After you add or update packs, or replace artwork in a collection, choose Library › Rescan Library (or Rescan All in Settings › Library). This re-reads the metadata, rebuilds the artwork index and deletes the saved copies of box art and screenshots. New artwork files are found without a rescan.
