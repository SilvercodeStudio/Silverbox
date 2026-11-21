# Settings

Open Settings with Command-Comma.

## General

- **App icon** — amber or green. The Dock and the About window show the chosen icon, and the screen behind it in the About window and on the welcome glows in its color; the buttons and highlights stay amber with either one. The Finder always shows the amber icon, and only that icon follows the icon style chosen in System Settings › Appearance (dark, clear or tinted).
- **Appearance** — light, dark, or matching the system.
- **Menu music** — on or off, its volume, and whether it keeps playing when another app is in front. MP3 and the other formats macOS plays, Ogg Vorbis, and MOD, S3M, XM and IT tracker modules play; AMF modules and VOC files are listed but skipped.
- **Videos** — the app that plays videos: the macOS default for MP4 files, unless you choose one. Other… in the list takes any app. QuickTime Player cannot play some videos, such as MP4 files with VP9 video; VLC plays them all. DVD disc images always open in VLC.
- **Playing** — whether to show the launch options dialog before each game. The dialog offers the game's versions, full screen or a window, the shader or filter, and the emulator, like the menus eXoDOS shows in its console window. Configure in a game's menu opens the same dialog to save choices for that game.
- **Library view** — whether hidden games appear in the library.
- **Game controller** — the controllers Silverbox sees. Help › Keyboard Shortcuts shows what each button does, with the names of the connected controller's buttons.
- **Updates** — check for a new version of Silverbox once a day. At its second launch, Silverbox asks whether to; this box changes the answer. **Check for Updates…** in the Silverbox menu checks at once. An update that arrives while a game runs, or while a game installs, downloads or uninstalls, waits for it to end before Silverbox opens again. A copy built from the source code does not check, and has no Check for Updates….

## Library

Each collection, with how many titles it holds (games, and the books, magazines, soundtracks and videos beside them). Open one to change its name or its folder, to turn it off, to see which of its parts were found, to add path substitutions, or to remove it. Remove Collection… asks first, and deletes nothing: the folder stays, and so do the games installed from it. Add Collection… and Rescan All are below the list. If you choose a folder inside a collection, such as `eXo` or `Data`, or the folder around one, Silverbox takes the collection.

Then the local data folder (the default one, the one you chose, or Other… to choose another), where new games are installed, and whether aria2 is there to download the games an eXoDOS Lite collection leaves out (it notices aria2 installed while the tab is open). Installed games, save backups, edited configs, unpacked soundtracks, caches, launch configs and logs are kept in the local data folder; favorites, play history and settings stay on this Mac. Choosing another folder does not move what is already there. If you moved or renamed the folder, choose it again: the collections set up inside it follow. See Collections and the local data folder.

## Emulators

Each emulator that was found, with its icon and version; rest the pointer on it for the path of its program. A missing one says how many games need it with your settings (rest the pointer on the number for the packs and platforms), with a link to get it. Choose… takes the app or the program inside it. Silverbox notices an emulator you install while this tab is open.

- **DOSBox Staging and DOSBox-X**, and which one to use by default: the build eXo picks for each game, or always one of them. DOSBox Staging also shows whether it can use FluidSynth.
- **86Box**, for the eXoWin9x games that need it.
- **ScummVM**, and a ScummVM daily build for the games that need it.
- **Spatterlight**, for eXoIF.
- **GSplus**, for eXoAppleIIGS, and the Apple IIGS ROM that MAME needs for the 74 eXoAppleIIGS games eXo runs in it (Add ROM…).
- **RetroArch** (with its cores folder), **Dolphin**, **MAME** and **Mednafen**, for console, computer and arcade platforms.
- **Platforms** — each console, computer and arcade platform with the emulator and core that run it. A platform set to Automatic follows the library's `Emulators.xml`, matched to the Mac emulators found here. Show only the platforms that are not ready, or filter them by name. The button at the end of a row holds extra arguments for the emulator's command line, once you have chosen an emulator for the platform. A platform whose core is missing has an Open RetroArch button: download the core there, under Online Updater › Core Downloader.

## Display & Sound

The defaults for every launch: full screen or window, window size, aspect ratio correction, CRT shader (DOSBox Staging), graphics filter (DOSBox-X), the start-up banner, and how to play General MIDI music. The launch options dialog starts from these values. Under General MIDI, a line says whether your DOSBox Staging can use FluidSynth; it updates by itself if you install FluidSynth or a newer DOSBox Staging while Settings is open.
