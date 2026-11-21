# Changelog

What changed in each version of Silverbox.

## 0.5 (not released yet)

### Added

- eXoDOS Lite: installing a game that the collection leaves out downloads
  it first, from the eXoDOS torrent that Lite includes, as eXo does on
  Windows. Downloads need aria2 (`brew install aria2`); the welcome screen
  and Settings › Library say whether it is found. A stopped download
  resumes on the next try.
- eXoAppleIIGS games play: 386 of the 460 in GSplus, with eXo's settings
  and the Apple IIGS ROM that eXo ships, and the other 74 in MAME, once
  you add the one ROM file that current MAME needs and eXo cannot ship
  (Settings › Emulators › Add ROM…). The launch options show eXo's
  instructions for a game, such as which program on the disk to open, and
  let you choose between its parts where eXo offers a menu.
- Help › Report a Problem… opens a new GitHub issue in your browser,
  filled in with the version, your Mac, your collections' packs and the
  emulators found. Help › Send Feedback… opens a new discussion. Nothing
  is sent until you submit it.
- Box art and screenshots from a network share load much faster after
  the first time: Silverbox keeps small copies of them on this Mac (up to
  about 300 MB). Rescan Library deletes them.
- Silverbox can update itself. Silverbox › Check for Updates… looks for a
  new version, and Settings › General can check once a day. An update
  waits for running games and installations before Silverbox opens again.
  Only the copy from getsilverbox.app checks; one built from the source
  code does not.
- Help › Support Silverbox and the About window's Leave a Tip button open
  a page where you can leave a tip. Silverbox stays free.

- Back and Forward, as in a browser: two arrows in the toolbar,
  Command-[ and Command-] (or Command-Left and Command-Right), and
  buttons 4 and 5 of a mouse. They move between the sections, searches
  and game pages you showed, and select the game you had selected
  there.
- A game's right-click menu can show the keys of its commands, such as
  Command-Down for Open Game Page: turn it on in Settings › General.
- Add Collection… takes the right folder when you choose one a level
  off: a folder inside a collection, such as `eXo` or `Data`, or the
  folder around one collection. The welcome screen and Settings say so
  while a chosen folder is read.
- Settings › Emulators shows what a missing emulator costs ("666 games
  need it", with the packs they come from when the pointer rests on it;
  the number follows your DOSBox setting), says so when eXoWin9x lacks
  DOSBox-X, and its list of platforms can show only those that are not
  ready, or those with a name you type. A platform whose RetroArch core
  is missing has an Open RetroArch button.

### Changed

- The accent is amber with either app icon. The green icon now changes
  the Dock and the About window only, so green always means "installed",
  "found" or "ready". Pop-up buttons and plain buttons have the standard
  macOS look; amber is for the main button, the selection and links.
- Status has a colored mark and plain text: a green check, a yellow
  warning triangle with a dark "!" or a red cross. A warning no longer looks like a
  button.
- A search counts against the section it searches ("13 of 517"), and
  lists the best title matches first: "Ultima" before "Ultimate", and
  both before a match by developer or publisher.
- A game page takes the place of the inspector, which showed the same
  things beside it, and has the status chips and the favorite and edit
  buttons itself. Its picture has no black bars beside it.
- "Silverbox" in the About window and "Welcome to Silverbox" are in
  VT323, the terminal font of the website's headlines. With the green
  icon, the CRT band behind the icon glows green.
- The sidebar counts each collection's titles, which include its books,
  magazines, soundtracks and videos, and Settings › Library shows the
  same number. Playlists under a pack drop the repeated words: "MT-32",
  not "eXoDOS Games with MT-32", and "Installed Demos".
- The inspector: one "Never played" line for a game you have not played,
  one "Runs in" line for the emulator, Files closed until you open it, a
  fade where the row of thumbnails goes on, and the version menu as the
  second half of the Play button. "Not installed" and "Not Rated" are gone.
- The welcome screen has three steps: add a collection, choose where
  installed games go, and check the emulators. It names what eXoDOS
  needs; the other packs' emulators are one click away. A finished step
  has a check mark. Before a collection is added, the window leaves out
  the search field, the view controls and the inspector.
- Settings: emulators appear as apps, with icon and version, not as file
  paths. Each collection shows a summary of its parts ("All 16 parts
  found") and opens to its name, folder and substitutions; Remove
  Collection… asks first. The video player and the local data folder
  each have one pop-up button with Other…. The volume is dimmed while
  the music is off. The notes under the groups are shorter; the help has
  the details.
- The Keyboard Shortcuts window groups the keys (Browsing, Game, Media,
  Music, View) and names the buttons of the controller that is connected.
- Windows and sheets open without a focus ring on their first button or
  link.
- Silverbox is free software under the GNU General Public License,
  version 3 or later. About › Acknowledgments › License… shows the
  copyright notice and the full text of the license. Contributions come
  in under the terms in CONTRIBUTING.md.
- A new app icon: a floppy disk, in amber or green.
- Help › Silverbox Website opens getsilverbox.app. The About window is
  new: the icon on a CRT screen, how many games the library holds and how
  many are installed and played, every emulator Silverbox uses, Website
  and Leave a Tip buttons, and a link to Silvercode Studio, which makes
  Silverbox. A click on the version copies it, with the Git commit of
  the build. The welcome screen opens with the same CRT screen.
- The help covers every eXo pack, explains how music plays in games, and
  has more troubleshooting, including every file Silverbox keeps and how
  to remove it. The Keyboard Shortcuts window now lists Play,
  Rescan Library and Show in Finder.

### Fixed

- The inspector's video is the selected game's. When you moved from one
  game with a video to another, the first game's video stayed.
- Failed or cancelled installations leave existing games alone and no longer
  appear as installed. Games that share files cannot be installed, removed
  or started over one another, including Windows 98 virtual machines. When
  you quit while games or jobs run, Silverbox asks first; "Quit Anyway"
  stops the jobs cleanly and leaves the games open; their files stay
  protected when Silverbox opens again, until the games quit.
- Save backups include hidden files and keep the previous backup if creating
  a replacement fails. Separate installations keep separate backups; older
  backups can still be restored, and so can a backup of a game in the
  collection's own folder made before its volume mounted under another
  name.
- Cancelling an installation or download before its helper starts no longer
  crashes the app. An extraction helper that cannot start reports its error
  instead of hanging. Damaged ZIP files report an error instead of crashing.
- Collections from downloads with the same folder name no longer reuse one
  another's setup. Finishing background jobs no longer restores stale
  collection information.
- Favorites and play history keep a previous readable copy, preserve damaged
  files for recovery, report save failures and finish saving before quitting.
  If the last save fails, you can stay and try again or quit without it.
- Collections set up inside the local data folder follow it when you move
  or rename that folder and choose it again in Settings. Before, they could
  not be found.
- General MIDI music in DOSBox Staging 0.83 and later now plays with the
  eXoDOS Sound Canvas SoundFont. These versions have FluidSynth built in,
  but Silverbox looked only for a separate FluidSynth and fell back to the
  macOS synthesizer. Settings › Display & Sound now shows which one plays,
  and notices a change while it is open.
- A collection whose folder is missing, or is not a library, says so in
  plain words in Settings. When its drive or network share connects,
  for example after the Mac wakes, the collection loads by itself a few
  seconds later; so does a local data folder on that drive.
- A collection on a network share that is not connected has a Connect
  button in Settings › Library, and Try Again in the window connects too:
  Silverbox remembers each share it has read from.
- The Finder can eject a collection's drive or share while Silverbox is
  open. Before, the menu music kept a file open there, even when paused,
  and the Finder refused.
- Adding a collection that Silverbox set up in a separate folder, such as
  one in the local data folder's Collections, finds the download's game
  archives again. Before, its games could not be installed.
- The install sheet no longer names the eXoDOS folder for games from other
  packs.
- Artwork added to a region folder, such as `Box - Front/North America`,
  now shows without Rescan Library.
- Games that start in RetroArch open in front of Silverbox. Before, its
  window could open behind, where RetroArch pauses, so the game seemed to
  hang. The launch log now shows RetroArch's messages, such as a missing
  BIOS file.
- Games from a LaunchBox library that start in RetroArch get the BIOS
  files their core needs from the library's own RetroArch, copied into
  RetroArch's system folder when they are missing there. A game whose
  core needs a file found in neither place says "BIOS missing".
- eXoIF's Atari 8-bit versions no longer change RetroArch's system folder
  setting. eXo's Atari ROMs are copied into RetroArch's system folder
  instead, where it has none.
- Silverbox finds RetroArch Nightly, the build for Apple silicon, in the
  Applications folder.

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
