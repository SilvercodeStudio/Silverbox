# Troubleshooting

## A game does not start, or quits at once

Right-click the game and choose **Show Last Launch Log…**: the sheet shows the emulator's output and the command line that started it, with a **Show Log** button in the bar while the game runs. **Copy as Markdown** copies a report with the emulator, command line, config, notes and the end of the log, ready to paste into a bug report. A game that exits with an error opens this sheet by itself. The files are in the local data folder: each game has a log in `Logs`, and the generated configuration is in `Launch` next to it.

## Saves are not kept

If the game is unpacked inside a read-only eXoDOS folder, Silverbox mounts a writable overlay from the local data folder's `Overlay` folder. Saves go there. Games installed by Silverbox are unpacked into the local data folder and can be written to directly.

## Box art is missing

Artwork is found by file name, the same way LaunchBox does it. The first scan of a large collection on a slow drive can take a minute; the index is then saved, so later launches are fast. If artwork was added to the collection, choose Library › Rescan Library.

## The emulator is not found

Set the location of DOSBox Staging, DOSBox-X or 86Box in Settings › Emulators. Either the application bundle or the executable inside it can be chosen. The same tab holds RetroArch, Dolphin, MAME and Mednafen for other platforms.

## A console game says its core is not installed

RetroArch cores are downloaded inside RetroArch (Online Updater › Core Downloader). Settings › Emulators shows the cores folder Silverbox reads and how many cores it found; choose another folder there if RetroArch keeps its cores elsewhere. The platform list on the same tab lets you pick any installed core for a platform.

## Menu music does not play

Ogg Vorbis tracks and MOD, S3M, XM and IT modules play through decoders built into Silverbox. AMF modules and VOC sound files are listed but skipped, and the music bar says so. Tracks in other formats (PSM, DSM) are not listed at all. If a track in a supported format stays silent, check the volume in the music bar and that menu music is on in Settings › General.
