# Emulators

## DOSBox for eXoDOS games

eXoDOS runs each game with a specific DOSBox build: DOSBox 0.74, DOSBox ECE, DOSBox Staging, DOSBox SVN Daum or DOSBox-X. On the Mac, Autoexec.Mac maps these to the two emulators it supports:

- **DOSBox Staging** for games set up for DOSBox 0.74, ECE and Staging. This is the default.
- **DOSBox-X** for games set up for SVN Daum and DOSBox-X.

Settings › Emulators lets you choose where each emulator is installed, and whether to follow the eXoDOS build or always use one emulator. Each game can be overridden in its launch options or in Edit Game Info.

## How a game is configured

Autoexec.Mac reads the game's `dosbox.conf` from the collection and translates it for the chosen emulator: paths become Mac paths, settings that no longer exist are dropped or renamed, and your display choices are layered on top. The translated configuration is written to the local data folder's `Launch` folder before each start.

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
