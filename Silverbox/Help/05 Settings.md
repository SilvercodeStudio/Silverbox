# Settings

Open Settings with Command-Comma.

## General

- **App icon** — amber or green, for the Dock and the About window. The Finder always shows the amber one.
- **Appearance** — light, dark, or matching the system.
- **Menu music** — on or off, its volume, and whether it keeps playing when another app is in front. MP3 and the other formats macOS plays, Ogg Vorbis, and MOD, S3M, XM and IT tracker modules play; AMF modules and VOC files are listed but skipped.
- **Videos** — the app that plays videos: the macOS default for MP4 files, unless you choose one. Other… in the list takes any app. QuickTime Player cannot play some videos, such as MP4 files with VP9 video; VLC plays them all. DVD disc images always open in VLC.
- **Playing** — whether to show the launch options dialog before each game. The dialog offers the game's versions, full screen or a window, the shader or filter, and the emulator, like the menus eXoDOS shows in its console window. Configure in a game's menu opens the same dialog to save choices for that game.
- **Library view** — whether hidden games appear in the library, and whether a game's right-click menu shows keyboard shortcuts (off by default, as usual on the Mac).
- **Game controller** — the controllers Silverbox sees. Help › Keyboard Shortcuts shows what each button does, with the names of the connected controller's buttons.
- **Updates** — check for a new version of Silverbox once a day. Silverbox asks the second time you open it; you can change your answer here. **Check for Updates…** in the Silverbox menu checks right away. If an update arrives while a game is running or installing, Silverbox waits for it to finish before restarting. A copy built from source doesn't check for updates.

## Library

This tab lists each collection and how many titles it holds (games, plus any books, magazines, soundtracks and videos). Open one to rename it, change its folder, turn it off, see which of its parts were found, add path substitutions, or remove it. Remove Collection… asks first and deletes nothing: the folder stays, and so do the games you installed from it. Add Collection… and Rescan All are below the list.

Below that are the local data folder (the default, the one you chose, or Other… to pick another), where new games are installed, and whether aria2 is installed for downloading eXoDOS Lite games. Installed games, save backups, edited configs, unpacked soundtracks, caches, launch configs and logs are kept in the local data folder; favorites, play history and settings stay on this Mac. Choosing another folder does not move what is already there. If you moved or renamed the folder, choose it again: the collections set up inside it follow. See Collections and the local data folder.

## Emulators

This tab shows each emulator Silverbox found, with its icon and version; hover over one to see where it is. A missing emulator says how many of your games need it (hover over the number for the breakdown) and links to where you can get it. Choose… takes the app or the program inside it, and Silverbox picks up an emulator you install while the tab is open.

- **DOSBox Staging and DOSBox-X**, and which one to use by default: the build eXo picks for each game, or always one of them. DOSBox Staging also shows whether it can use FluidSynth.
- **86Box**, for the eXoWin9x games that need it.
- **ScummVM**, and a ScummVM daily build for the games that need it.
- **Spatterlight**, for eXoIF.
- **GSplus**, for eXoAppleIIGS, and the Apple IIGS ROM that MAME needs for the 74 eXoAppleIIGS games eXo runs in it (Add ROM…).
- **RetroArch** (with its cores folder), **Dolphin**, **MAME** and **Mednafen**, for console, computer and arcade platforms.
- **Platforms** — each console, computer and arcade platform with the emulator and core that run it. A platform set to Automatic follows the library's `Emulators.xml`, matched to the Mac emulators found here. Show only the platforms that are not ready, or filter them by name. The button at the end of a row holds extra arguments for the emulator's command line, once you have chosen an emulator for the platform. A platform whose core is missing has an Open RetroArch button: download the core there, under Online Updater › Core Downloader.

## Display & Sound

The defaults for every launch: full screen or window, window size, aspect ratio correction, CRT shader (DOSBox Staging), graphics filter (DOSBox-X), the start-up banner, and how to play General MIDI music. The launch options dialog starts from these values. Under General MIDI, a line says whether your DOSBox Staging can use FluidSynth, and it updates if you install FluidSynth or a newer DOSBox Staging while Settings is open.
