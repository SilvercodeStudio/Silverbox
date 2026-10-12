# Troubleshooting

## A game does not start, or quits at once

Open the local data folder's `Logs` folder. Each game has a log with the exact command line and the emulator's output. The generated configuration is in the `Launch` folder next to it.

## Saves are not kept

If the game is unpacked inside a read-only eXoDOS folder, eXo Client mounts a writable overlay from the local data folder's `Overlay` folder. Saves go there. Games installed by eXo Client are unpacked into the local data folder and can be written to directly.

## Box art is missing

Artwork is found by file name, the same way LaunchBox does it. The first scan of a large collection on a slow drive can take a minute; the index is then saved, so later launches are fast. If artwork was added to the collection, choose Library › Rescan Library.

## The emulator is not found

Set the location of DOSBox Staging or DOSBox-X in Settings › Emulators. Either the application bundle or the executable inside it can be chosen. The same tab holds RetroArch, Dolphin, MAME and Mednafen for other platforms.

## A console game says its core is not installed

RetroArch cores are downloaded inside RetroArch (Online Updater › Core Downloader). Settings › Emulators shows the cores folder eXo Client reads and how many cores it found; choose another folder there if RetroArch keeps its cores elsewhere. The platform list on the same tab lets you pick any installed core for a platform.

## Menu music does not play

Tracks in Ogg Vorbis format are not supported by macOS and are skipped.
