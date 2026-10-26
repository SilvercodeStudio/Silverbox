# Milestones

The first goal is a Mac client for the eXo collections, as LaunchBox is on
Windows: read an eXo download or a set-up collection in place, set it up
without Windows, and start each game in a Mac emulator with eXo's settings.
Milestones 1–8 reach that goal for eXoDOS and the Windows packs. Milestone 9
covers eXo's other packs, 10 the console libraries, and 11 the polish and
release work before the app goes to the eXo team.

| #   | Milestone                                   | Status      |
| --- | ------------------------------------------- | ----------- |
| 1   | Read an eXoDOS collection                   | Done        |
| 2   | Launch eXoDOS games in DOSBox               | Done        |
| 3   | Local data folder and installing            | Done        |
| 4   | Several collections                         | Done        |
| 5   | Music, soundtracks, videos and extras       | Done        |
| 6   | Keyboard and game controller                | Done        |
| 7   | Set up an eXo download on the Mac           | Mostly done |
| 8   | eXoWin9x and eXoWin3x                       | Done        |
| 9   | eXo's other packs                           | In progress |
| 10  | Console, computer and arcade libraries      | In progress |
| 11  | Polish and release                          | In progress |
| —   | Later                                       | Not started |

## 1. Read an eXoDOS collection — done

- LaunchBox XML (platforms, parents, playlists), a library snapshot and
  queries, and a JSON cache keyed by the data files' sizes and dates.
- Media by LaunchBox's naming: box art, screenshots, region folders, images
  named after the ROM file; manuals, music and videos by launcher name, then
  title.
- Grid and list views, the sidebar, search, sorting, the inspector.
- Read-only libraries (a read-only volume or a network share).

## 2. Launch eXoDOS games in DOSBox — done

- The eXoDOS config translated for DOSBox Staging and DOSBox-X; the build
  index (`dosbox.txt`) picks the emulator.
- The launch options dialog: global options and per-game overrides; edited
  configs in `Overrides/`.
- eXo's in-game MIDI menus patched for DOSBox Staging (`MIDIBatchPatcher`).
- Launch logs, the log sheet and the Markdown launch report.
- `make sweep` translates every config in the mounted library.

## 3. Local data folder and installing — done

- `Games/`, `Overlay/`, `Saves/`, `Overrides/` and the caches in the local data
  folder, which can move to another drive; "install in place" as an option.
- Installs as background jobs with progress, Cancel, Dock progress and a
  notification; uninstall keeps changed files in `Saves/`.

## 4. Several collections — done

- Several `LibraryCollection`s in one `Library`; collection-scoped game IDs;
  path substitutions for relocated `Games` folders and drive letters.
- Add a collection by dropping a folder on the window.

## 5. Music, soundtracks, videos and extras — done

Done:

- Menu music: MP3 and AAC through macOS, Ogg Vorbis (stb_vorbis), MOD, S3M,
  XM and IT (libxmp-lite).
- The eXoDOS soundtracks as albums, unpacked on play.
- Videos in a Mac video player; manuals, images and extras in Quick Look.

Not planned:

- The full libxmp (without its depackers) in place of libxmp-lite, for the
  two AMF variants and Epic MegaGames PSM: ten more eXoDOS titles (Crusader,
  The Civil War, Jazz Jackrabbit). DSM (four titles) would need libmodplug.
  Left out by choice (2026-10-24): the gain is small.

## 6. Keyboard and game controller — done

- Arrows, Return, Space and Escape in the grid and list; menu shortcuts; the
  Keyboard Shortcuts window; controller buttons as key presses.

## 7. Set up an eXo download on the Mac — mostly done

Done:

- `EXoDownload` and `EXoSetup`: what eXo's `Setup <pack>.bat` does, in place
  or into `Collections/<name>`; nested zips, XML merges, add-on platforms,
  CP437 file names.
- Checked against the Windows setup of eXoDOS v6
  (`matchesTheWindowsSetup`).

Not yet:

- eXoDOS Lite: download a game on demand when it is not in the download.
  This is the app's first network request: revise the website's privacy
  page and its "send anything about me?" answer, and follow AGENTS.md's
  network rules.
- BitTorrent downloads of the packs (later).

## 8. eXoWin9x and eXoWin3x — done

- eXoWin9x: Windows 98 on DOSBox-X from a differencing disk; about thirty
  games in 86Box. Confirmed by the user on 2026-10-13 (Marathon 2 in
  DOSBox-X, Locus in 86Box). Network play is not supported; games start in
  Solo mode.
- eXoWin3x: each game boots its own Windows 3.1 in DOSBox Staging or
  DOSBox-X. Set up from the download and spot-checked on 2026-10-15.

## 9. eXo's other packs — in progress

Done:

- eXoDemoScene in DOSBox (about 99%; the three MartyPC demos are not
  supported).
- eXoScummVM in ScummVM, with an optional daily build for five games.
- eXoIF: story files in Spatterlight, MS-DOS versions in DOSBox, Commodore,
  ZX Spectrum, Apple II, Atari 8-bit, Amstrad CPC and Amiga versions in
  RetroArch (about 1,500 of 2,331 games).
- eXoAppleIIGS: set up and install.

Not yet:

- eXoAppleIIGS launching: GSplus configs for about 84% of the games; later
  MAME for the rest (needs a current `apple2gs` ROM set).
- eXoIF's BBC Micro, TRS-80, Dragon/CoCo, Oric and TI-99 versions (MAME or
  native emulators).
- The eXoScummVM hint files (UHS).

## 10. Console, computer and arcade libraries — in progress

Done:

- LaunchBox libraries for consoles; `EmulatorAssignmentResolver` maps the
  library's `Emulators.xml` to the Mac emulators that are installed;
  `RomLaunchPlanner` builds the command line for RetroArch, Dolphin, MAME and
  Mednafen.

Not yet:

- Play the games for real: nothing has been played through these routes.
- ROM-folder collections: plain `Games/<Platform>` folders with no LaunchBox
  XML, and single titles set up by hand.

## 11. Polish and release — in progress

Silverside (the same author's CD ripper) is the reference.

Done:

- Status chips, the launch log sheet, background jobs, sidebar counts,
  empty states, list header sorting, About with Acknowledgments and the
  License (2026-10-23); the welcome view with emulator status, short
  warning chips with help tags, help tags on disabled controls, and
  emulators noticed while the app is open (2026-10-25).
- `LICENSE` (MIT; the name and the icon artwork excluded), `CHANGELOG.md`,
  this file, `make lint`, `make install-app` (registers the app with Launch
  Services), the copyright and the Games category in the app's Info.plist,
  Swift 6 language mode for the app, `-dataPath` and `-demoLibrary`; the
  template test targets removed from the Xcode project.
- The name Silverbox (bundle ID `app.getsilverbox.Silverbox`) and the
  floppy disk icon in amber and green, for version 0.3 (2026-10-25); the
  project, target, modules, folders and settings key renamed to match.

Not yet:

- The website for getsilverbox.app: `docs/site`, the Pages workflow and
  `make site` are in place (2026-10-25). Still to do: current screenshots in
  both appearances, the Pages and DNS setup, and the download link once
  there is a signed build.
- A release script shared with Silverside: archive, Developer ID signing,
  notarization, stapling, a DMG.
- A CI workflow for `swift test` and `make lint`.

## Later

- Couch mode: a full-screen, controller-first view.
- Metadata and media scraping for games outside the eXo collections.
- An iPhone and iPad companion that browses the library from the Mac.
