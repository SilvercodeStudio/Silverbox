# Playing games

Select a game and press Play, press Command-Return, or double-click its box.

## Installing

An eXo game must be installed before it plays the first time. Press Install… in the inspector, or Play, and confirm. Silverbox unpacks the game's archive into the local data folder (or the eXoDOS folder, see Settings). If the collection ships an update for the game, it is applied automatically. If setup left the game's manuals and extras packed, they are unpacked too. If you uninstalled the game before and kept a backup, you can restore your saved progress. In an eXoDOS Lite collection, the game's archive downloads first; see Collections and the local data folder.

Installing runs in the background, so you can keep browsing and install other games at the same time. A bar at the bottom of the window shows each installation: its progress, the step under way and the time it has taken. Downloads run one at a time; the others wait their turn. **Cancel** stops the installation and removes its temporary files. The game becomes installed only when unpacking finishes; an existing installation is left alone. A cancelled download keeps what it has, and continues the next time you install the game. The Dock icon shows the progress too. When an installation finishes while you work in another app, the Dock icon bounces and a notification says so; macOS asks once whether Silverbox may show notifications. With "Play when installation finishes" on, the game starts by itself. If an installation fails, its row stays in the bar with the reason until you dismiss it.

## The launch options dialog

Before a game starts, Silverbox shows its launch options. On Windows, eXoDOS asks the same questions in a console window when you play or configure a game. The dialog starts from the defaults in Settings › Display & Sound.

- **Version** — some games come in several editions, for example CGA, EGA and VGA releases, or original and patched versions. Games that show their version menu inside DOSBox, such as A-10 Tank Killer, still do so.
- **Full screen** or a window. In full screen the emulator scales the picture to your display.
- **Window size** — eXoDOS asks for your desktop resolution (less than 1080p, 1080p, or 4K) and sizes the window to match. Automatic lets DOSBox Staging choose a size for your screen; DOSBox-X uses the size in the game's config, which eXoDOS sets for a 1080p desktop. If the window is too large or too small, pick the next size down or up.
- **Aspect ratio correction** — DOS games were made for 4:3 monitors. With correction on, the picture keeps its original shape, and a widescreen display shows black bars at the sides. With it off, the picture is stretched to fill the screen, so circles become ovals. "As configured per game" keeps the game's own setting: on for almost every game, off for the few that do not work with it.
- **CRT shader** (DOSBox Staging) or **Graphics filter** (DOSBox-X). eXoDOS lets you pick a DOSBox scaler per game: none, Normal 2x/3x (nearest neighbour), HQ2x/3x (smoothed edges), 2xSaI and Super 2xSaI (heavy smoothing), AdvMAME 2x/3x (EPX) and TV 2x (scanlines). DOSBox Staging has no scalers; its shaders take that role, and the CRT shaders imitate a monitor of the period.
- **Emulator** — DOSBox Staging or DOSBox-X. The default follows the DOSBox build eXoDOS uses for the game and the policy in Settings › Emulators.

Turn on "Remember these choices for this game" to keep them for next time. **Configure…** in a game's context menu or the inspector opens the same dialog to save choices without starting the game, also before the game is installed. "Use Defaults" removes the saved choices. To skip the dialog, turn off "Show launch options before each game" in Settings › General.

## Windows 3.x games and demos

eXoWin3x games run in DOSBox, as eXoDOS games do: each game's archive holds its own Windows 3.1, which starts the game. eXoDemoScene demos also run in DOSBox, most of them in DOSBox-X, following the build eXo picks for each one. The launch options are the same as for eXoDOS games.

## Windows 9x games

eXoWin9x games run in Windows 98. eXo keeps Windows 98 on one shared disk image and each game on a disk of its own. Play installs the game the first time, as for eXoDOS games. Then DOSBox-X starts Windows 98 with the game's disk and CD attached, and Windows starts the game when its desktop is ready. To stop, close the emulator window.

Windows starts clean every time. Before each start, Silverbox makes a new, empty disk on top of the shared image, and Windows writes its changes there. Saved games go to the game's own disk and stay. If the game is already unpacked in a read-only collection, Silverbox copies the game's disk to the `Overlay` folder in the local data folder the first time, so that Windows can write to it.

About thirty games, such as Quake and Die Hard Trilogy, need a faster PC with a 3dfx Voodoo card. eXo runs these in 86Box. To play them, get 86Box from https://86box.net and put 86Box.app in the Applications folder. For these games, the launch options have only Full screen.

Network play is not available. Games that offer Solo, Host or Join on Windows start in Solo mode.

## ScummVM games

eXoScummVM games run in ScummVM. Get it from https://www.scummvm.org and put ScummVM.app in the Applications folder. Play installs the game the first time. Many games come in several versions, such as the DOS, Amiga and CD releases; the launch options list them under Version, with the first one chosen until you pick another. Where eXo asks for a music device (Sound Blaster, Roland MT-32, Sound Canvas and others) or for subtitles, the launch options ask too, and "Remember these choices" keeps the answers.

Window size works as in eXo: Small, Medium and Large scale the picture two, four or eight times; Automatic uses ScummVM's own setting. In the game, Control-F5 opens ScummVM's menu, for saving, loading and quitting.

The games use eXo's ScummVM settings, kept in the local data folder (`ScummVM/scummvm.ini`) apart from your own ScummVM settings. Saved games go to `Saves/ScummVM`, shared by every collection, as in eXo. A few games need ScummVM engines that its release builds leave out; to play them, choose a daily build of ScummVM in Settings › Emulators.

## Interactive fiction

eXoIF games come in versions for many computers: a game can have Commodore 64, ZX Spectrum, MS-DOS and story-file versions. The launch options list them all under Version. Story files (Infocom and other Z-code, Glulx, TADS, Hugo, Level 9, Magnetic Scrolls, Adrift) open in Spatterlight; get it from https://ccxvii.net/spatterlight/ and put it in the Applications folder. MS-DOS versions run in DOSBox. Versions for the Commodore 64 and 128, ZX Spectrum and ZX81, Apple II and Atari 8-bit run in RetroArch, with its cores installed from RetroArch's Online Updater; a C64 game on several disks gets a playlist, so the other disks are in RetroArch's Disk Control menu. Versions for other computers are marked "not supported on the Mac", with the reason. The RetroArch versions are new and not yet tested with many games; please report what you find. Unless you pick one, Play starts a Spatterlight version, else a DOS version, else a RetroArch one.

Spatterlight keeps its own windows, fonts and saved games. Closing Spatterlight ends the game for Silverbox.

## Apple IIGS games

eXoAppleIIGS games run in GSplus. Get it from https://github.com/digarok/gsplus and put GSplus.app in the Applications folder. It uses the Apple IIGS ROM that eXo ships, so you need nothing else. Play installs the game the first time.

Many games come with eXo's instructions, such as which program on the disk to open first or which drive holds the character disk; the launch options show them, under Version or Note. A few games come in parts, such as Cribbage King and Gin King; the launch options list them under Version. Full screen is the only display choice.

In GSplus, F4 opens its menu, where you can insert another disk; close the window to end the game. Games save to their disk images in the installed game's folder. For a game unpacked in a read-only collection, Silverbox copies its disks to the local data folder's `Overlay` folder first.

eXo runs ten games in GSport, the emulator GSplus grew out of; they run in GSplus too.

eXo runs 74 games, such as Gauntlet and Rastan, in MAME. Install MAME with Homebrew (`brew install mame`). eXo's MAME ROM set is for an older MAME, and current MAME needs one more file: `344s0047.bin`, the Apple IIGS character ROM (16 KB). Silverbox cannot include it. If you have it, or `apple2gs.zip` from a current MAME ROM set, add it in Settings › Emulators › eXoAppleIIGS games with Add ROM…; Silverbox checks the file and keeps a copy in the local data folder's `MAME` folder. Until then, these games say "ROM missing".

## Music in games

DOS games make their music in one of a few ways, chosen in the game's setup program or in eXo's sound menu for the game:

- **Sound Blaster or AdLib** music is synthesized by DOSBox itself. Most DOS games use it.
- **Roland MT-32** music plays through DOSBox's MT-32 emulation, with the ROM files in the collection's `eXo/mt32` folder.
- **General MIDI** (also called Sound Canvas) plays through FluidSynth with the eXoDOS Sound Canvas SoundFont, as on Windows. DOSBox-X and DOSBox Staging 0.83 or later have FluidSynth built in. Without it, General MIDI plays through the macOS synthesizer, which sounds different. Settings › Display & Sound says which one your DOSBox Staging uses, and lets you choose.

This applies to every game that runs in DOSBox: eXoDOS, eXoWin3x, eXoDemoScene, eXoWin9x in DOSBox-X, and the MS-DOS versions of eXoIF games. When eXo's sound menu for a game sets General MIDI, DOSBox Staging would not accept the setting it writes, so Silverbox changes that line in the game's files to the General MIDI device you chose. ScummVM games use ScummVM's own music settings. The menu music you hear while browsing is not MIDI and does not use the SoundFont.

## Uninstalling

Quit the game, then choose Uninstall from its context menu. Games using the same files cannot be installed, removed or started over one another; this also protects the Windows 98 virtual machines. If you quit Silverbox while games or installations run, it asks first: "Quit Anyway" stops the installations and setup cleanly, and the games stay open. Their files stay protected when Silverbox opens again, until the games quit. Silverbox offers to back up your saved games and any changed files first. The backup is a small archive under the local data folder's `Saves/Installations` folder, kept separately for each installation, and it is offered for restore the next time you install the game. If the game was installed in the collection's own folder and the collection's drive now mounts under another name, the backup from before is still offered. Older backups in `Saves` are still offered. If a backup fails, the game and the previous backup are left in place.

## Extras and manuals

The inspector lists the game's manual and extras: reference cards, maps, cluebooks and guide books. Click one for Quick Look, or use the context menu to open it in another app.

## Soundtracks

The Soundtracks platform holds album zips of FLAC and MP3 tracks that eXoDOS plays with foobar2000. Play unpacks the album into the local data folder the first time, then plays it in the bar at the bottom of the window: previous, pause, next, a position slider and the volume. The inspector and the game page list the tracks; click one to start there. The album keeps playing while you browse, pauses when a game starts, and stops with the X in the bar or Music › Stop Album. Menu music waits until the album stops. Right-click an album to open its tracks in another app: Open in … names the app macOS uses for those files, Open With lists every app registered for them plus Other… to pick any app, and Remove Unpacked Album deletes the local copy; the zip in the library stays.

## Videos

The MS-DOS Videos platform holds documentaries, interviews and old video catalogs that eXoDOS plays with VLC. Play opens the video in the app chosen in Settings › General, or in the app macOS uses for MP4 files, such as QuickTime Player. QuickTime Player cannot play some of these videos, such as A Visit to id Software, which uses VP9 video; choose VLC in Settings, or right-click the video and use Open With to pick a player once. Open With lists every app registered for video files, plus Other… to pick any app.

When an entry has several videos (episodes or discs), a list opens first; choose one and press Return, or double-click it. Some entries, such as BBS: The Documentary and Get Lamp, are DVD disc images. QuickTime Player cannot play these, so Play opens them in VLC; install VLC from videolan.org to play them.

## Menu music

Many games have a music track that plays while you browse. MP3 and the other formats macOS plays work directly; Ogg Vorbis tracks and MOD, S3M, XM and IT tracker modules play through decoders built into Silverbox. AMF modules and VOC files are listed but skipped. Use the bar at the bottom of the window to pause the music or change the volume, or turn it off in Settings › General. The music pauses when another app comes to the front and resumes when you come back, unless Music › Play in Background is on.
