# Playing games

Select a game and press Play, press Command-Return, or double-click its box.

## Installing

The first time you play a game, Autoexec.Mac unpacks its archive into the local data folder (or the eXoDOS folder, see Settings). If the collection ships an update for the game, it is applied automatically. If setup left the game's manuals and extras packed, they are unpacked too. If you uninstalled the game before and kept a backup, you can restore your saved progress.

## The launch options dialog

Before a game starts, Autoexec.Mac shows its launch options. On Windows, eXoDOS asks the same questions in a console window when you play or configure a game. The dialog starts from the defaults in Settings › Display & Sound.

- **Version** — some games come in several editions, for example CGA, EGA and VGA releases, or original and patched versions. Games that show their version menu inside DOSBox, such as A-10 Tank Killer, still do so.
- **Full screen** or a window. In full screen the emulator scales the picture to your display.
- **Window size** — eXoDOS asks for your desktop resolution (less than 1080p, 1080p, or 4K) and sizes the window to match. Automatic lets DOSBox Staging choose a size for your screen; DOSBox-X uses the size in the game's config, which eXoDOS sets for a 1080p desktop. If the window is too large or too small, pick the next size down or up.
- **Aspect ratio correction** — DOS games were made for 4:3 monitors. With correction on, the picture keeps its original shape, and a widescreen display shows black bars at the sides. With it off, the picture is stretched to fill the screen, so circles become ovals. "As configured per game" keeps the game's own setting: on for almost every game, off for the few that do not work with it.
- **CRT shader** (DOSBox Staging) or **Graphics filter** (DOSBox-X). eXoDOS lets you pick a DOSBox scaler per game: none, Normal 2x/3x (nearest neighbour), HQ2x/3x (smoothed edges), 2xSaI and Super 2xSaI (heavy smoothing), AdvMAME 2x/3x (EPX) and TV 2x (scanlines). DOSBox Staging has no scalers; its shaders take that role, and the CRT shaders imitate a monitor of the period.
- **Emulator** — DOSBox Staging or DOSBox-X. The default follows the DOSBox build eXoDOS uses for the game and the policy in Settings › Emulators.

Turn on "Remember these choices for this game" to keep them for next time. **Configure…** in a game's context menu or the inspector opens the same dialog to save choices without starting the game, also before the game is installed. "Use Defaults" removes the saved choices. To skip the dialog, turn off "Show launch options before each game" in Settings › General.

## Windows 9x games

eXoWin9x games run in Windows 98. eXo keeps Windows 98 on one shared disk image and each game on a disk of its own. Play installs the game the first time, as for eXoDOS games. Then DOSBox-X starts Windows 98 with the game's disk and CD attached, and Windows starts the game when its desktop is ready. To stop, close the emulator window.

Windows starts clean every time. Before each start, Autoexec.Mac makes a new, empty disk on top of the shared image, and Windows writes its changes there. Saved games go to the game's own disk and stay. If the game is already unpacked in a read-only collection, Autoexec.Mac copies the game's disk to the `Overlay` folder in the local data folder the first time, so that Windows can write to it.

About thirty games, such as Quake and Die Hard Trilogy, need a faster PC with a 3dfx Voodoo card. eXo runs these in 86Box. To play them, get 86Box from https://86box.net and put 86Box.app in the Applications folder. For these games, the launch options have only Full screen.

Network play is not available. Games that offer Solo, Host or Join on Windows start in Solo mode.

## ScummVM games

eXoScummVM games run in ScummVM. Get it from https://www.scummvm.org and put ScummVM.app in the Applications folder. Play installs the game the first time. Many games come in several versions, such as the DOS, Amiga and CD releases; the launch options list them under Version, with the first one chosen until you pick another. Where eXo asks for a music device (Sound Blaster, Roland MT-32, Sound Canvas and others) or for subtitles, the launch options ask too, and "Remember these choices" keeps the answers.

Window size works as in eXo: Small, Medium and Large scale the picture two, four or eight times; Automatic uses ScummVM's own setting. In the game, Control-F5 opens ScummVM's menu, for saving, loading and quitting.

The games use eXo's ScummVM settings, kept in the local data folder (`ScummVM/scummvm.ini`) apart from your own ScummVM settings. Saved games go to `Saves/ScummVM`, shared by every collection, as in eXo. A few games need ScummVM engines that its release builds leave out; to play them, choose a daily build of ScummVM in Settings › Emulators.

## Interactive fiction

eXoIF games come in versions for many computers: a game can have Commodore 64, ZX Spectrum, MS-DOS and story-file versions. The launch options list them all under Version. Story files (Infocom and other Z-code, Glulx, TADS, Hugo, Level 9, Magnetic Scrolls, Adrift) open in Spatterlight; get it from https://ccxvii.net/spatterlight/ and put it in the Applications folder. MS-DOS versions run in DOSBox. Versions for the Commodore 64 and 128, ZX Spectrum and ZX81, Apple II and Atari 8-bit run in RetroArch, with its cores installed from RetroArch's Online Updater; a C64 game on several disks gets a playlist, so the other disks are in RetroArch's Disk Control menu. Versions for other computers are marked "not supported on the Mac", with the reason. Unless you pick one, Play starts a Spatterlight version, else a DOS version, else a RetroArch one.

Spatterlight keeps its own windows, fonts and saved games. Closing Spatterlight ends the game for Autoexec.Mac.

## Uninstalling

Choose Uninstall from the game's context menu. Autoexec.Mac offers to back up your saved games and any changed files first. The backup is a small archive in the local data folder's `Saves` folder, and it is offered for restore the next time you install the game.

## Extras and manuals

The inspector lists the game's manual and extras: reference cards, maps, cluebooks and guide books. Click one for Quick Look, or use the context menu to open it in another app.

## Soundtracks

The Soundtracks platform holds album zips of FLAC and MP3 tracks that eXoDOS plays with foobar2000. Play unpacks the album into the local data folder the first time, then plays it in the bar at the bottom of the window: previous, pause, next, a position slider and the volume. The inspector and the game page list the tracks; click one to start there. The album keeps playing while you browse, pauses when a game starts, and stops with the X in the bar or Music › Stop Album. Menu music waits until the album stops. Right-click an album to open its tracks in another app: Open in … names the app macOS uses for those files, Open With lists every app registered for them plus Other… to pick any app, and Remove Unpacked Album deletes the local copy; the zip in the library stays.

## Videos

The MS-DOS Videos platform holds documentaries, interviews and old video catalogs that eXoDOS plays with VLC. Play opens the video in the app chosen in Settings › General, or in the app macOS uses for MP4 files, such as QuickTime Player. QuickTime Player cannot play some of these videos, such as A Visit to id Software, which uses VP9 video; choose VLC in Settings, or right-click the video and use Open With to pick a player once. Open With lists every app registered for video files, plus Other… to pick any app.

When an entry has several videos (episodes or discs), a list opens first; choose one and press Return, or double-click it. Some entries, such as BBS: The Documentary and Get Lamp, are DVD disc images. QuickTime Player cannot play these, so Play opens them in VLC; install VLC from videolan.org to play them.

## Menu music

Many games have a music track that plays while you browse. MP3 and the other formats macOS plays work directly; Ogg Vorbis tracks and MOD, S3M, XM and IT tracker modules play through decoders built into Autoexec.Mac. AMF modules and VOC files are listed but skipped. Use the bar at the bottom of the window to pause the music or change the volume, or turn it off in Settings › General. The music pauses when another app comes to the front and resumes when you come back, unless Music › Play in Background is on.
