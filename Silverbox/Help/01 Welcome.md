# Welcome to Silverbox

Silverbox is a Mac front-end for the eXo game preservation collections: eXoDOS, eXoWin3x, eXoWin9x, eXoDemoScene, eXoScummVM, eXoIF and eXoAppleIIGS. It reads a collection in place, shows the games with their box art, screenshots, manuals, extras, music and videos, and starts each game in a Mac emulator with the settings eXo uses on Windows. LaunchBox libraries from Windows work too.

The games, media and emulators are not part of Silverbox. You need:

- An eXo collection: a download as it came (Silverbox sets it up, as eXo's setup does on Windows), or a collection already set up. eXoDOS Lite leaves out the games; Silverbox downloads each one when you install it, with aria2 (`brew install aria2`).
- DOSBox Staging for eXoDOS, eXoWin3x and eXoDemoScene games, and DOSBox-X for eXoWin9x games and the DOS games that eXo runs in DOSBox-X.
- For the other packs: 86Box (about thirty eXoWin9x games), ScummVM (eXoScummVM), Spatterlight (eXoIF), GSplus (eXoAppleIIGS) and RetroArch (eXoIF's 8-bit versions, and consoles). The eXoAppleIIGS games that eXo runs in MAME also need MAME and one ROM file you supply.

Until you add a collection, the window shows these two steps, with each emulator found or a link to get it. Emulators you install while Silverbox is open show up without a restart.

This is an early version. Expect rough edges, and please report what you find.

## Credits

The eXo collections are projects of the eXo team. Learn more and support them at https://www.retro-exo.com. Silverbox is not affiliated with or endorsed by the eXo project. Silverbox's own website is https://getsilverbox.app (Help › Silverbox Website).

Emulation is provided by DOSBox Staging (https://www.dosbox-staging.org), DOSBox-X (https://dosbox-x.com), 86Box (https://86box.net), ScummVM (https://www.scummvm.org), Spatterlight (https://ccxvii.net/spatterlight/), GSplus (https://github.com/digarok/gsplus) and RetroArch (https://www.retroarch.com). Game metadata and artwork come from the collections' LaunchBox data.
