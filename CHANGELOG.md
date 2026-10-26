# Changelog

What changed in each version of Silverbox.

## 0.3

### Changed

- A new app icon: a floppy disk, in amber or green. The highlight colours
  match it.

### Fixed

- Collections set up inside the local data folder follow it when you move
  or rename that folder and choose it again in Settings. Before, they could
  not be found.

## 0.2

### Added

- **Installs run in the background.** A bar at the bottom of the window shows
  each installation with its progress and a Cancel button, which removes the
  half-made game folder. The Dock icon shows the progress, and a notification
  says when an installation or a setup finishes while you work in another
  app.
- **Launch log:** after a launch, the log shows the command line and the
  emulator's output. It opens by itself when the emulator stops with an
  error, and Copy as Markdown makes a report to paste into a bug report.
  Open it again from a game's context menu or the bar of the game that plays.
- **Status at a glance:** the details panel says whether a game is
  installed, which emulator runs it, and whether that emulator is on this
  Mac. The sidebar counts the games in each row, shows each collection's size
  and whether it is read-only, and names the local data folder.
- **A welcome screen** until you add a collection: it explains the two kinds
  of folder you can add (an eXo download as it came, or a collection that is
  already set up) and lists the emulators each eXo pack needs, each found or
  with a link to get it.
- Settings, the welcome screen and the details panel notice an emulator you
  install while the app is open.
- Click a column header in the list to sort by it.
- The About window shows the acknowledgments and the license.
- Box art and screenshots named after the game's file, as Skraper names
  them, now show when no image is named after the title.

### Changed

- Views with nothing to show say why, in the system's style.
- A warning in the details panel is a short label; rest the pointer on it
  for the whole reason, which also shows under Mac emulator. Buttons and
  versions that cannot be used say why in the same way.

### Fixed

- General MIDI chosen in eXo's in-game setup menus now plays in DOSBox
  Staging. The menus set a MIDI device that Staging does not accept, so the
  game had no MIDI music; Silverbox now changes that line to the General
  MIDI device you chose in the launch options.

## 0.1

The first version.

### Added

- **Your eXo collections on the Mac.** Choose an eXoDOS folder (or drop it on
  the window) and the app reads it in place: the games, box art, screenshots,
  manuals, menu music, soundtracks and videos. The folder can be on a
  read-only drive or a network share; the app never changes it. Load several
  collections at once, including a LaunchBox library for consoles.
- **Set up an eXo download without Windows.** Point the app at an untouched
  eXoDOS, eXoWin3x, eXoWin9x or other eXo pack download, and it does what
  eXo's setup does on Windows: in place, or into the local data folder when
  the download is read-only.
- **Play the games** in Mac emulators that you install yourself:
  - eXoDOS and eXoDemoScene in DOSBox Staging or DOSBox-X, with each game's
    configuration translated from eXo's.
  - eXoWin3x in Windows 3.1, and eXoWin9x in Windows 98, on DOSBox-X; about
    thirty eXoWin9x games in 86Box.
  - eXoScummVM in ScummVM, with an optional daily build for the five games
    the release build cannot run.
  - eXoIF story files in Spatterlight, their MS-DOS versions in DOSBox, and
    their 8-bit versions in RetroArch.
- **Install and uninstall games** from their zips, into the local data folder
  or in place. Uninstall keeps a copy of the files a game changed, such as
  saved games.
- **Launch options** for each game: the version, when eXo has several, and
  the DOSBox display and MIDI settings (full screen, window size, aspect,
  shader, scaler, General MIDI device), kept for the next launch. Edit a
  game's configuration by hand if you want.
- **Browse** in a grid or a list, by platform, playlist, eXo pack, eXo's
  favorites, your favorites, installed games, or recently played. Search,
  sort, and see the other versions of a game in other packs.
- **Menu music** in the library, from eXo's MP3, Ogg Vorbis and tracker
  files, and the eXoDOS **soundtracks** as albums.
- **Keyboard and game controller** navigation of the whole library, with a
  Keyboard Shortcuts window and Quick Look for manuals, images and extras.
- A **local data folder** for installed games, saved-game backups and
  caches, which you can move to another drive.
- Light and dark appearance, an amber or a green app icon, and a Help window.
