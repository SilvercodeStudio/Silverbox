#!/bin/sh
# A release of Silverbox, as docs/internal/Releasing.md has it, up to the pushed tag: steps 1 to
# 4 here, and the commands for the rest printed at the end. The maintainer runs it, by hand;
# an agent never does (it tags and pushes). It asks before each step that changes the
# repository or sends something away, and it can be run again after a stop: it goes on from
# what is already done.
#
#   1. The version: the one in the code (scripts/version.sh), checked against CHANGELOG.md's
#      newest heading, the last tag, and the update feed. Enter takes it; another one replaces it.
#   2. Finish it: the CHANGELOG heading dated, the website's version lines and download links,
#      then make format, lint, test, and build, and the commit "Finish <version>: ..." (the editor
#      opens for the rest).
#   3. make dist: the notarized disk image, and the feed with the new item.
#   4. The feed checked: one new item, of this version, with the right download URL and size,
#      signed, and the whole feed signed; the earlier items unchanged.
#   5. The tag, annotated, on the commit that make dist built; then it is pushed.
#
#   RELEASE_DATE=2026-11-20   the date in the CHANGELOG heading (default: today)
#   PYTHON, NOTARY_PROFILE    passed to make dist (see scripts/dist.sh)
set -eu

cd "$(dirname "$0")/.."
FEED_FILE=docs/site/appcast.xml
SITE=docs/site/index.html
RELEASES=https://github.com/SilvercodeStudio/Silverbox/releases/download
KEY_ACCOUNT=silverbox
DIST=build/dist

die() {
    echo "release.sh: $*" >&2
    exit 1
}
step() { printf '\n== %s\n' "$*"; }
# ask QUESTION: true for a yes.
ask() {
    printf '%s [y/N] ' "$1"
    read -r answer
    case "$answer" in y | Y | yes) return 0 ;; *) return 1 ;; esac
}
# newer A B: true if version A is higher than B, comparing part by part, as Sparkle does.
newer() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        n = split(a, x, "."); m = split(b, y, ".")
        for (i = 1; i <= (n > m ? n : m); i++) {
            if (x[i] + 0 > y[i] + 0) exit 0
            if (x[i] + 0 < y[i] + 0) exit 1
        }
        exit 1
    }'
}
# highest: the highest of the versions on standard input, one a line.
highest() { grep -E '^[0-9]+(\.[0-9]+)*$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1; }

# ---- Where the release stands
step "Checking the repository"
[ "$(git symbolic-ref --short HEAD 2>/dev/null)" = main ] || die "not on main"
git fetch -q origin
git merge-base --is-ancestor origin/main HEAD || die "main is behind origin/main: pull first"
# A run that stopped after make dist left only the feed changed; anything else must be committed.
changes=$(git status --porcelain)
case "$changes" in
"") ;;
" M $FEED_FILE" | "?? $FEED_FILE") ;;
*) die "there are changes that are not committed:
$changes" ;;
esac
scripts/version.sh check

# ---- 1. The version
step "The version"
code=$(scripts/version.sh)
heading=$(grep -m 1 '^## ' CHANGELOG.md || true)
heading_version=$(echo "$heading" | sed -n 's/^## \([0-9][0-9.]*\) .*/\1/p')
last_tag=$(git tag --list | highest || true)
last_feed=$( (grep -o '<sparkle:version>[^<]*' "$FEED_FILE" 2>/dev/null || true) | sed 's/.*>//' | highest || true)
echo "In the code:        $code"
echo "CHANGELOG.md:       $heading"
echo "The last tag:       ${last_tag:-none}"
echo "The feed's newest:  ${last_feed:-none (no feed yet)}"

VERSION=$code
printf 'Version to release [%s]: ' "$VERSION"
read -r typed
if [ -n "$typed" ] && [ "$typed" != "$VERSION" ]; then
    [ -z "$changes" ] || die "the feed is already changed for $VERSION; finish that release, or revert the feed"
    case "$heading" in
    *"(not released yet)") ;;
    *) die "CHANGELOG.md's newest version is finished already: $heading" ;;
    esac
    scripts/version.sh set "$typed" >/dev/null
    # The newest heading takes the new number, if it is the unreleased one.
    case "$heading" in
    *"(not released yet)")
        sed -i '' "s/^## $heading_version (not released yet)\$/## $typed (not released yet)/" CHANGELOG.md
        heading_version=$typed
        ;;
    esac
    VERSION=$typed
    echo "Changed to $VERSION in the code$([ "$heading_version" = "$typed" ] && echo " and CHANGELOG.md")."
fi

[ "$heading_version" = "$VERSION" ] || die "CHANGELOG.md's newest heading is not $VERSION: $heading"
# The last tag can be this version's, made by a run that stopped before its push: the checks
# below allow it only on HEAD and only while origin does not have it.
[ -z "$last_tag" ] || [ "$last_tag" = "$VERSION" ] || newer "$VERSION" "$last_tag" ||
    die "$VERSION is not higher than the last tag, $last_tag"
[ -z "$last_feed" ] || [ "$last_feed" = "$VERSION" ] || newer "$VERSION" "$last_feed" ||
    die "$VERSION is not higher than the feed's $last_feed: Sparkle would never offer it"
[ -z "$(git ls-remote --tags origin "refs/tags/$VERSION")" ] ||
    die "origin has the tag $VERSION already: the rest of the release is by hand (docs/internal/Releasing.md)"
# A tag made here before a push that did not happen must be on HEAD.
if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null &&
    [ "$(git rev-parse "$VERSION^{commit}")" != "$(git rev-parse HEAD)" ]; then
    die "the tag $VERSION exists already, on another commit"
fi

DMG="$DIST/Silverbox-$VERSION.dmg"
NOTES="$DIST/feed/Silverbox-$VERSION.md"
built=0
if [ -n "$changes" ] && [ -f "$DMG" ] && grep -q "<sparkle:version>$VERSION<" "$FEED_FILE"; then built=1; fi

# ---- 2. Finish the version
if grep -q "^## $VERSION (not released yet)\$" CHANGELOG.md; then
    step "Finishing $VERSION"
    date=${RELEASE_DATE:-$(date +%Y-%m-%d)}
    sed -i '' "s/^## $VERSION (not released yet)\$/## $VERSION ($date)/" CHANGELOG.md
    sed -i '' -E "s/Version [0-9]+(\.[0-9]+)* · Free and open source/Version $VERSION · Free and open source/" "$SITE"
    [ "$(grep -c "Version $VERSION · Free and open source" "$SITE")" -eq 2 ] ||
        die "$SITE should have two version lines with $VERSION; look at it"
    # The Download for Mac button links to the disk image, which step 5 uploads before main goes
    # out. Before the first release, the button links to the releases page and a "Coming soon"
    # banner is on the page: change both by hand first (Releasing.md).
    ! grep -q "Coming soon" "$SITE" || die "$SITE still has its \"Coming soon\" banner; take it out first"
    sed -i '' -E "s#releases/download/[0-9.]+/Silverbox-[0-9.]+\.dmg#releases/download/$VERSION/Silverbox-$VERSION.dmg#g" "$SITE"
    grep -q "releases/download/$VERSION/Silverbox-$VERSION.dmg" "$SITE" ||
        die "$SITE has no download link to Silverbox-$VERSION.dmg; look at it"
    finished="CHANGELOG.md $SITE $(git diff --name-only -- Silverbox.xcodeproj)"
    make format
    # make format must change nothing else: a change would go out unseen in the release.
    others=$(git status --porcelain | awk '{ print $2 }' | grep -vxF -e CHANGELOG.md -e "$SITE" \
        -e Silverbox.xcodeproj/project.pbxproj || true)
    [ -z "$others" ] || die "make format changed other files; look at them and commit them first:
$others"
    make lint
    make test
    make build
    git --no-pager diff --stat
    git --no-pager diff -- CHANGELOG.md "$SITE" | grep '^[-+][^-+]' || true
    ask "Commit these as \"Finish $VERSION: ...\" (the editor opens for the rest of the message)?" ||
        die "stopped; the changes are not committed"
    # shellcheck disable=SC2086 # one argument for each file
    git commit -e -m "Finish $VERSION: " -- $finished
elif ! grep -q "^## $VERSION ([0-9-]*)\$" CHANGELOG.md; then
    die "CHANGELOG.md has no heading for $VERSION"
else
    echo "$VERSION is finished already: $(git log -1 --format='%h %s')"
fi

# ---- 3. make dist
if [ "$built" = 1 ]; then
    step "make dist is done already: $DMG"
else
    step "make dist (notarization takes a few minutes, twice)"
    ask "Archive, notarize, and add $VERSION to the feed?" || die "stopped before make dist"
    make dist
fi
[ -f "$DMG" ] && [ -f "$NOTES" ] || die "make dist left no $DMG or $NOTES"

# ---- 4. The feed
step "Checking the feed"
# The commit in the app is the one to tag: make dist builds only a clean tree.
app_commit=$(/usr/libexec/PlistBuddy -c "Print :SilverboxCommit" "$DIST/export/Silverbox.app/Contents/Info.plist")
case "$(git rev-parse HEAD)" in
"$app_commit"*) ;;
*) die "the app was built from $app_commit, not from HEAD ($(git rev-parse --short HEAD))" ;;
esac
earlier=$(mktemp)
git show "HEAD:$FEED_FILE" >"$earlier" 2>/dev/null || : >"$earlier"
signature=$("${PYTHON:-python3}" -I scripts/check_feed.py "$FEED_FILE" "$earlier" "$VERSION" \
    "$RELEASES/$VERSION/Silverbox-$VERSION.dmg" "$(stat -f %z "$DMG")") || {
    rm -f "$earlier"
    die "the feed is not right; do not edit it by hand (docs/internal/Releasing.md, step 3)"
}
rm -f "$earlier"
# Sparkle's own check of both signatures, with the public half of the Keychain's key.
build_dir=$(xcodebuild -project Silverbox.xcodeproj -scheme Silverbox -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILD_DIR =/ {print $2; exit}')
SIGN="$build_dir/../../SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[ -x "$SIGN" ] || die "no sign_update at $SIGN"
"$SIGN" --account "$KEY_ACCOUNT" --verify "$DMG" "$signature" || die "the disk image's signature does not verify"
"$SIGN" --account "$KEY_ACCOUNT" --verify "$FEED_FILE" || die "the feed's signature does not verify"
git --no-pager diff --stat -- "$FEED_FILE"
echo "The feed is good: $FEED_FILE (not committed)."

# ---- 5. The tag
step "The tag"
echo "HEAD: $(git log -1 --format='%h %s')"
if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    echo "The tag $VERSION is on it already."
else
    ask "Tag $VERSION on it?" || die "stopped before the tag"
    git tag -a "$VERSION" -m "$VERSION"
fi
ask "Push the tag $VERSION to origin?" || die "stopped: the tag is here only (git push origin $VERSION)"
git push origin "$VERSION"

# ---- The rest, by hand
size=$(stat -f %z "$DMG")
step "Done to the tag. The rest, in this order, so that the feed never names a missing file:"
cat <<END
5. The disk image on GitHub:
     gh release create $VERSION $DMG --title "Silverbox $VERSION" --notes-file $NOTES
   then check the download (HTTP 200 and $size bytes at the end):
     curl -sIL $RELEASES/$VERSION/Silverbox-$VERSION.dmg | grep -iE '^(HTTP|content-length)'
6. The feed (and the website's version, in the Finish commit) go out with main:
     git commit -m "Publish $VERSION in the update feed" -- $FEED_FILE
     git push origin main
   then, after the Pages workflow (a minute or two):
     curl -s https://getsilverbox.app/appcast.xml | grep -c '<sparkle:version>$VERSION<'
7. Check for Updates... on a Mac with the release before $VERSION (none before the first).
8. Start the next version:
     scripts/version.sh next
END
