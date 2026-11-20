# Troubleshooting

## A game does not start, or quits at once

Right-click the game and choose **Show Last Launch Log…**: the sheet shows the emulator's output and the command line that started it, with a **Show Log** button in the bar while the game runs. **Copy as Markdown** copies a report with the emulator, command line, config, notes and the end of the log, ready to paste into a bug report. A game that exits with an error opens this sheet by itself. The files are in the local data folder: each game has a log in `Logs`, and the generated configuration is in `Launch` next to it.

## A collection says its folder is not there

The collection's folder was moved or renamed, or its drive is not connected. Connect the drive, or choose the folder again in Settings › Library. If the collection was set up inside the local data folder and you moved or renamed that folder, choose the data folder again instead: its collections follow it.

## Saves are not kept

If the game is unpacked inside a read-only eXoDOS folder, Silverbox mounts a writable overlay from the local data folder's `Overlay` folder. Saves go there. Games installed by Silverbox are unpacked into the local data folder and can be written to directly.

## Box art is missing

Artwork is found by file name, the same way LaunchBox does it. The first scan of a large collection on a slow drive can take a minute; the index is then saved, so later launches are fast. Silverbox finds new artwork files by itself. If you replaced an image with another one of the same name, choose Library › Rescan Library.

Box art and screenshots on a network share load slowly the first time. Silverbox then keeps a small copy of each on this Mac, so they show at once the next time.

## The emulator is not found

Set the emulator's location in Settings › Emulators: DOSBox Staging, DOSBox-X, 86Box, ScummVM, Spatterlight, RetroArch, Dolphin, MAME or Mednafen. Either the app or the program inside it can be chosen. Emulators in the Applications folder are found without this.

## General MIDI music sounds wrong

If a General MIDI game sounds thin or different from Windows, check the line under General MIDI in Settings › Display & Sound. When it says DOSBox Staging has no FluidSynth, the game plays through the macOS synthesizer. Update to DOSBox Staging 0.83 or later, which has FluidSynth built in, or install FluidSynth with Homebrew (`brew install fluid-synth`). A game set up for Sound Blaster or AdLib music does not use MIDI at all; choose General MIDI in the game's setup if it offers it. See Playing Games › Music in games.

## A game download stays at "Looking for peers"

aria2 asks the torrent's trackers for other computers that share the game, one tracker at a time. Some of them no longer answer, so the first download can wait a minute or more before it starts; aria2 keeps a list of peers in the local data folder's `BitTorrent` folder, and later downloads start sooner. If a download does not start after several minutes, Cancel it and install the game again: what was downloaded is kept. A firewall that blocks aria2 can also stop it; allow incoming connections for aria2c if macOS asks.

## A console game says its core is not installed

RetroArch cores are downloaded inside RetroArch (Online Updater › Core Downloader). Settings › Emulators shows the cores folder Silverbox reads and how many cores it found; choose another folder there if RetroArch keeps its cores elsewhere. The platform list on the same tab lets you pick any installed core for a platform.

## Menu music does not play

Ogg Vorbis tracks and MOD, S3M, XM and IT modules play through decoders built into Silverbox. AMF modules and VOC sound files are listed but skipped, and the music bar says so. Tracks in other formats (PSM, DSM) are not listed at all. If a track in a supported format stays silent, check the volume in the music bar and that menu music is on in Settings › General.

## Report a problem

Help › Report a Problem… opens a new issue for Silverbox on GitHub in your browser. The issue has headings for you to fill in. At its end are Silverbox's version, your macOS version and Mac model, each collection's packs and number of games, and the emulators Silverbox found. It holds no file paths or collection names. Nothing is sent until you submit the issue, and you can change or delete any of it first. You need a GitHub account to submit.

For a game that does not start, add its launch report: right-click the game, choose **Show Last Launch Log…**, click **Copy as Markdown** and paste the report into the issue.

## Send feedback

Comments, ideas and questions that are not about a problem are welcome too. Help › Send Feedback… opens a new discussion for Silverbox on GitHub, with Silverbox's version and your macOS version at its end. As with a problem report, nothing is sent until you submit it.

## Where Silverbox keeps its files

In `~/Library/Application Support/Silverbox`:

- `user-library.json`: your favorites, play history, hidden and completed games, and the choices you made for each game. `user-library.json.previous` is the copy before the last change. If the file cannot be read, Silverbox keeps it aside as `user-library-unreadable-….json`.
- `running-games.json`: the games that were still running when Silverbox quit, so their files stay protected until they stop.

The local data folder is in the same place, unless Settings › Library moves it to another drive. It holds:

- `Games`: the games Silverbox installed.
- `Saves`: the backups of each game's changed files, made when you uninstall it, and ScummVM's saves.
- `Overrides`: the game settings you edited.
- `Overlay`: the files that games on a read-only collection change, and copies of Windows 98 disks.
- `Collections`: the collections Silverbox set up from an eXo download.
- `Soundtracks`: albums unpacked from the collections.
- `ScummVM` and `MAME`: those emulators' settings for eXo games, and the Apple IIGS ROM you added.
- `Launch` and `Logs`: the configuration and the emulator output of each launch.
- `LibraryCache` and `MediaIndex`: saved scans of the collections, so they load fast. Library › Rescan Library deletes them, and you can delete them at any time.
- `BitTorrent`: aria2's list of peers for game downloads.

Elsewhere:

- `~/Library/Preferences/app.getsilverbox.Silverbox.plist`: the settings and window positions.
- `~/Library/Caches/app.getsilverbox.Silverbox`: the Help window's cache, and in `Thumbnails` the small copies of box art and screenshots (up to about 300 MB; the oldest go first). Library › Rescan Library deletes the copies, and you can delete the folder at any time. An update that is downloading waits in the `org.sparkle-project.Sparkle` folder there.

Silverbox changes a collection only when you ask: a game download or "Install in place" puts the game in the collection, and setting up a download in place writes the setup there.

To remove Silverbox, quit it, move it to the Trash, and delete the `Silverbox` folder in Application Support, the local data folder if you moved it, and the preferences file and cache folder above. Your collections stay as they are. Keep the local data folder if you may install Silverbox again: it has your installed games and save backups.
