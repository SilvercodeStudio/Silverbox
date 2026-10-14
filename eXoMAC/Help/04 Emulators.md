# Emulators

## DOSBox for eXoDOS games

eXoDOS runs each game with a specific DOSBox build: DOSBox 0.74, DOSBox ECE, DOSBox Staging, DOSBox SVN Daum or DOSBox-X. On the Mac, Autoexec.Mac maps these to the two emulators it supports:

- **DOSBox Staging** for games set up for DOSBox 0.74, ECE and Staging. This is the default.
- **DOSBox-X** for games set up for SVN Daum and DOSBox-X.

Settings › Emulators lets you choose where each emulator is installed, and whether to follow the eXoDOS build or always use one emulator. Each game can be overridden in its launch options or in Edit Game Info.

## Windows 98 for eXoWin9x games

eXoWin9x games boot Windows 98 from disk images in the collection's `eXo/emulators` folder:

- **DOSBox-X** runs most of them, from each game's `Play.conf`.
- **86Box** runs about thirty games that need a Pentium-class PC with a 3dfx Voodoo card, from each game's `Play.cfg`. It uses the ROM and CMOS files in `eXo/emulators/86Box98`.

You cannot choose another emulator for these games. Get 86Box from https://86box.net and set its location in Settings › Emulators if it is not in the Applications folder.

## ScummVM for eXoScummVM games

eXoScummVM games run in **ScummVM**. eXo keeps a list of the ScummVM id for every game and version (`eXo/util/scummvm.txt`) and small files in each version's folder for its platform, picture and sound options; Autoexec.Mac reads them as eXo's launcher does. eXo ships several Windows builds of ScummVM because some games broke in newer releases; the Mac uses the one ScummVM you have.

Five games need engines that ScummVM's release builds leave out until they are finished: In Cold Blood, The Adventures of Robin Hood, Star Trek: 25th Anniversary, Lost Eden and Ultima I. Choose a daily build from https://buildbot.scummvm.org as "ScummVM daily build" in Settings › Emulators; it is used only for games the release build cannot run.

## How a game is configured

Autoexec.Mac reads the game's `dosbox.conf` (eXoWin9x: `Play.conf` or `Play.cfg`) from the collection and translates it for the chosen emulator: paths become Mac paths, settings that no longer exist are dropped or renamed, and your display choices are layered on top. The translated configuration is written to the local data folder's `Launch` folder before each start.

## Music and MIDI

Games set up for the Roland MT-32 use the emulated MT-32 with the ROM files in the collection's `eXo/mt32` folder.

General MIDI games use the collection's Sound Canvas SoundFont through FluidSynth when it is available. DOSBox Staging loads FluidSynth from a separately installed library; install it with Homebrew (`brew install fluid-synth`). Without it, General MIDI plays through the macOS synthesizer.

## Consoles, computers and arcade

Games from a LaunchBox library, such as a console collection, start in the emulator assigned to their platform:

- **RetroArch** runs most platforms through its libretro cores. Install the cores you need in RetroArch itself (Online Updater › Core Downloader); Autoexec.Mac finds them in RetroArch's cores folder.
- **Dolphin** runs Nintendo GameCube and Wii games.
- **MAME** runs arcade ROM sets.
- **Mednafen** covers a few more consoles from the command line.

A platform without a choice of its own follows the library's `Emulators.xml`, mapped to the Mac emulators installed here: the RetroArch core named there is used when it is installed, a renamed core such as FBNeo stands in for its old name, and a core with no Mac build (the Dolphin core, for example) hands over to the standalone app. Settings › Emulators lists every platform with its status, and lets you pick another emulator or core, or add arguments.

Full screen follows the Display & Sound setting. RAR archives cannot be opened by any of these emulators, and Dolphin needs plain disc images rather than zip files.
