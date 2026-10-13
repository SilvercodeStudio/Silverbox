# Playing games

Select a game and press Play, press Command-Return, or double-click its box.

## Installing

The first time you play a game, Autoexec.Mac unpacks its archive into the local data folder (or the eXoDOS folder, see Settings). If the collection ships an update for the game, it is applied automatically. If you uninstalled the game before and kept a backup, you can restore your saved progress.

## The launch options dialog

Before a game starts, Autoexec.Mac shows its launch options. On Windows, eXoDOS asks the same questions in a console window when you play or configure a game. The dialog starts from the defaults in Settings › Display & Sound.

- **Version** — some games come in several editions, for example CGA, EGA and VGA releases, or original and patched versions. Games that show their version menu inside DOSBox, such as A-10 Tank Killer, still do so.
- **Full screen** or a window. In full screen the emulator scales the picture to your display.
- **Window size** — eXoDOS asks for your desktop resolution (less than 1080p, 1080p, or 4K) and sizes the window to match. Automatic lets DOSBox Staging choose a size for your screen; DOSBox-X uses the size in the game's config, which eXoDOS sets for a 1080p desktop. If the window is too large or too small, pick the next size down or up.
- **Aspect ratio correction** — DOS games were made for 4:3 monitors. With correction on, the picture keeps its original shape, and a widescreen display shows black bars at the sides. With it off, the picture is stretched to fill the screen, so circles become ovals. "As configured per game" keeps the game's own setting: on for almost every game, off for the few that do not work with it.
- **CRT shader** (DOSBox Staging) or **Graphics filter** (DOSBox-X). eXoDOS lets you pick a DOSBox scaler per game: none, Normal 2x/3x (nearest neighbour), HQ2x/3x (smoothed edges), 2xSaI and Super 2xSaI (heavy smoothing), AdvMAME 2x/3x (EPX) and TV 2x (scanlines). DOSBox Staging has no scalers; its shaders take that role, and the CRT shaders imitate a monitor of the period.
- **Emulator** — DOSBox Staging or DOSBox-X. The default follows the DOSBox build eXoDOS uses for the game and the policy in Settings › Emulators.

Turn on "Remember these choices for this game" to keep them for next time. **Configure…** in a game's context menu or the inspector opens the same dialog to save choices without starting the game, also before the game is installed. "Use Defaults" removes the saved choices. To skip the dialog, turn off "Show launch options before each game" in Settings › General.

## Uninstalling

Choose Uninstall from the game's context menu. Autoexec.Mac offers to back up your saved games and any changed files first. The backup is a small archive in the local data folder's `Saves` folder, and it is offered for restore the next time you install the game.

## Extras and manuals

The inspector lists the game's manual and extras: reference cards, maps, cluebooks and guide books. Click one for Quick Look, or use the context menu to open it in another app.

## Soundtracks

The Soundtracks platform holds album zips of FLAC and MP3 tracks that eXoDOS plays with foobar2000. Play unpacks the album into the local data folder the first time, then plays it in the bar at the bottom of the window: previous, pause, next, a position slider and the volume. The inspector and the game page list the tracks; click one to start there. The album keeps playing while you browse, pauses when a game starts, and stops with the X in the bar or Music › Stop Album. Menu music waits until the album stops. Right-click an album to open its tracks in another app: Open in … names the app macOS uses for those files, Open With lists every app registered for them plus Other… to pick any app, and Remove Unpacked Album deletes the local copy; the zip in the library stays.

## Menu music

Many games have a music track that plays while you browse. MP3 and the other formats macOS plays work directly; Ogg Vorbis tracks and MOD, S3M, XM and IT tracker modules play through decoders built into Autoexec.Mac. AMF modules and VOC files are listed but skipped. Use the bar at the bottom of the window to pause the music or change the volume, or turn it off in Settings › General. The music pauses when another app comes to the front and resumes when you come back, unless Music › Play in Background is on.
