# Releasing Silverbox

How to make a release of the app, publish it in the update feed, and start
the next version; and how to update Sparkle. Silverside's release works the
same way; its `docs/internal/Sparkle.md` has the reasons behind the choices.

## Versions

- **One version:** `MARKETING_VERSION` in
  `Silverbox.xcodeproj/project.pbxproj` (Debug and Release).
  `CURRENT_PROJECT_VERSION` is `$(MARKETING_VERSION)`, so `CFBundleVersion`
  is the same number. `scripts/version.sh` prints it, `scripts/version.sh
  set 0.5` changes it, and `make lint` fails when the two configurations
  differ or the build number is not the version.
- **Each release must be higher.** Sparkle compares `CFBundleVersion` part by
  part (0.10 is higher than 0.9) and offers only a higher one. A version that
  is in the feed can never be built again with other contents.
- **The tag** is the plain version (`0.5`, no "v"), annotated, on the commit
  that `make dist` built.
- **CHANGELOG.md:** the newest entry is `## 0.5 (not released yet)` while
  work goes on, and `## 0.5 (2026-11-30)` in the release's commit. The entry
  is also the update's notes, which Sparkle's window shows as Markdown: write
  it for the people who use Silverbox.

## Set up a Mac for releases (once)

- **Xcode** signed in with the team (5A35N7A73U) and its Developer ID
  certificate.
- **The notary profile:** `xcrun notarytool store-credentials silverbox
  --apple-id <Apple ID> --team-id 5A35N7A73U` (an app-specific password).
- **Sparkle's private key,** in the login Keychain under the account
  `silverbox` (not Silverside's key). The first time: `generate_keys
  --account silverbox` makes the key pair and prints the public key; put it
  in `SUPublicEDKey` in `Silverbox/Info.plist`. Back up the private key at
  once, out of the repository: `generate_keys --account silverbox -x <file>`,
  into the password manager, then delete the file. On another Mac:
  `generate_keys --account silverbox -f <file>`. `generate_keys --account
  silverbox -p` must print the `SUPublicEDKey` in `Silverbox/Info.plist`.
  `generate_keys` is in the package's download
  (`SourcePackages/artifacts/sparkle/Sparkle/bin/` in the project's
  DerivedData, after a build). **Never make a new key after the first
  release:** every installed copy accepts only updates signed with this one.
- **GitHub's CLI:** `brew install gh`, then `gh auth login`.
- **Python 3.15 or later** (`brew install python`). `make dist` uses the
  first `python3` on the PATH, or `PYTHON=<path>`, and makes its own
  environment for dmgbuild in `build/tools` the first time.

Every step of a release that publishes something (a tag, a push, `gh`, the
feed's commit) is done by hand, by the maintainer, never by an agent.

## The first release

Before the first `scripts/release.sh`:

1. On `docs/site/index.html`, take out the "Coming soon" banner, and point
   the Download for Mac buttons at the disk image:
   `https://github.com/SilvercodeStudio/Silverbox/releases/download/<version>/Silverbox-<version>.dmg`.
   `release.sh` stops while the banner is there, and changes the version in
   these links at each release after.
2. Replace the site's screenshots (`make site-shots`).
3. Try a whole build without publishing: `ALLOW_DIRTY=1 FEED=0 make dist`.

## A release

`scripts/release.sh` does steps 1 to 4 and prints the commands for the rest.
Run it yourself, in Terminal: it asks before each step that changes the
repository or sends something away (the commit, `make dist`, the tag, its
push), and after a stop it goes on from what is done. It proposes the version
in the code, checks it against CHANGELOG.md, the last tag, and the feed, and
takes another if you type one. Its check of the feed is `scripts/check_feed.py`
and `sign_update --verify`. The steps by hand:

1. **Finish the version.** Date the CHANGELOG heading. Change the version in
   `docs/site/index.html`: two lines ("Version 0.5 · Free and open source…")
   and the Download for Mac links. Run `make format`, `make lint`, `make
   test`, and `make build`, and commit ("Finish 0.5: …"). The site goes out
   with `main` in step 6, after the disk image is uploaded, so its links
   never name a missing file.
2. **`make dist`.** It needs a clean tree. It archives, exports with Developer
   ID, checks the signature, the build number, and Sparkle (the framework,
   the feed URL, a real public key, no XPC services), notarizes the app and
   staples it, puts it in a disk image, signs, notarizes, and staples that
   too (two waits of a few minutes each), checks it, and adds the version to
   the feed. The Keychain asks once whether `generate_keys` and
   `generate_appcast` may use the key: Always Allow. It leaves
   `build/dist/Silverbox-0.5.dmg`, the notes
   `build/dist/feed/Silverbox-0.5.md`, and a changed `docs/site/appcast.xml`.
   - `make dist FEED=0` makes the disk image only, for a build that is not to
     be published. `NOTARIZE=0` stops after the export and its checks.
   - `make dist` deletes `build/dist` first: upload the last release's disk
     image before the next try.
3. **Look at the feed's change** (`git diff docs/site/appcast.xml`): one new
   item with the version, the download URL under `releases/download/0.5/`,
   the notes, and `sparkle:edSignature` on the enclosure; the signature of
   the whole feed at the end. **Do not edit the feed:** a change breaks its
   signature, and every copy of the app then refuses it. To change the
   notes, edit the `.md` file in `build/dist/feed` and run `generate_appcast`
   again on that folder, with the options in `scripts/dist.sh`, then copy its
   `appcast.xml` to `docs/site`.
4. **Tag and push the tag:** `git tag -a 0.5 -m 0.5` on the commit that was
   built, then `git push origin 0.5`.
5. **Upload the disk image** before the feed names it: `gh release create 0.5
   build/dist/Silverbox-0.5.dmg --title "Silverbox 0.5" --notes-file
   build/dist/feed/Silverbox-0.5.md`. Check that the download works:
   `curl -sIL https://github.com/SilvercodeStudio/Silverbox/releases/download/0.5/Silverbox-0.5.dmg`
   ends in `200`, with the disk image's size.
6. **Publish the feed:** commit `docs/site/appcast.xml` alone ("Publish 0.5
   in the update feed") and push `main`. The Pages workflow publishes it in a
   minute or two; `curl -s https://getsilverbox.app/appcast.xml` then shows
   the new item.
7. **Check the update** on a Mac with the release before: Silverbox › Check
   for Updates… finds the new version, shows its notes, installs it, and
   opens it again; About shows the new version. Install a test copy from the
   disk image, or with the Finder or `ditto`: a copy that follows symbolic
   links (`cp -L`, some sync tools) breaks Sparkle.framework's signature.
8. **Start the next version:** `scripts/version.sh next` raises the version
   (0.5 to 0.6; `next 1.0` for another), and adds `## 0.6 (not released
   yet)` to CHANGELOG.md. Commit.

## When something goes wrong

- **Notarization fails:** `make dist` prints Apple's log. Fix, commit, and run
  it again; the version stays the same while nothing is published.
- **A published release is bad:** release a higher version with the fix.
  Sparkle never goes down a version. To stop offering the bad one at once,
  revert the feed's commit and push: the earlier feed is still signed.
- **The feed was edited by hand:** run `generate_appcast` again (step 3), or
  revert it.

## The disk image's window

`Packaging/dmg_settings.py` lays it out for dmgbuild, over `background.png`
and `background@2x.png`. `make_dmg_background.py` draws the pictures (it needs
numpy and Pillow: `python3 -m venv /tmp/bg && /tmp/bg/bin/pip install numpy
pillow`, then `/tmp/bg/bin/python Packaging/make_dmg_background.py
Packaging`). The window's size and the icons' places are in both files; keep
them the same. Finder writes the names under the icons in black on a
picture, in both appearances, so the picture must be light behind them. To
look at the window without a release, make a disk image from any copy of the
app with the dmgbuild in `build/tools`:

```sh
build/tools/dmgbuild-1.6.7/bin/dmgbuild -s Packaging/dmg_settings.py \
    -D app=<path to Silverbox.app> Silverbox /tmp/Try.dmg && open /tmp/Try.dmg
```

## Sparkle in the project

- The package is pinned to one version (2.10.1) in the app target only; the
  core does not link it. `AppUpdater` compiles without it (`#if
  canImport(Sparkle)`), so a checkout builds before the package resolves,
  but `make dist` refuses an app without the framework.
- `Silverbox/Info.plist` holds the Sparkle keys (`SUFeedURL`,
  `SUPublicEDKey`, `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`);
  Xcode merges it with the keys from the `INFOPLIST_KEY_` build settings.
- The build phase "Remove Sparkle's XPC services" runs
  `scripts/remove-sparkle-xpc.sh` after "Record the Git commit": an archive
  leaves the XPC services out (an app with no sandbox does not use them).
- Only an archive checks for updates (`SilverboxArchive`, from
  `scripts/record-commit.sh`).

To update Sparkle: read its release notes for changes to the XPC services,
the Info.plist keys, or the feed; change the version in Xcode (the project ›
Package Dependencies); `make build`, then `ALLOW_DIRTY=1 NOTARIZE=0 make
dist`, which fails if the XPC services are still in the app; if Sparkle's
`LICENSE` changed, copy it to `Silverbox/Licenses/Sparkle.txt`.
