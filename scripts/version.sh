#!/bin/sh
# The version of Silverbox: MARKETING_VERSION in the app's project, on its Debug and Release
# lines. CURRENT_PROJECT_VERSION must be $(MARKETING_VERSION), so CFBundleVersion is the same
# number: Sparkle compares it to find a newer version. make lint checks both. The website and
# CHANGELOG.md name the released version, which scripts/release.sh writes.
#
#   scripts/version.sh             print the version (it fails if the lines disagree)
#   scripts/version.sh check       the same, printing nothing when they agree
#   scripts/version.sh set 0.5     change the version
#   scripts/version.sh next [0.5]  start the next version after a release: set it (by default,
#                                  the last part raised by one), and add its heading,
#                                  "## 0.5 (not released yet)", to CHANGELOG.md
set -eu

cd "$(dirname "$0")/.."
PROJECT=Silverbox.xcodeproj/project.pbxproj

die() {
    echo "version.sh: $*" >&2
    exit 1
}

# Each value that the project gives a setting, one a line.
setting() { sed -n "s/^[[:space:]]*$1 = \"*\([^;\"]*\)\"*;\$/\1/p" "$PROJECT" | sort -u; }

current() {
    versions=$(setting MARKETING_VERSION)
    [ -n "$versions" ] || die "no MARKETING_VERSION in $PROJECT"
    if [ "$(printf '%s\n' "$versions" | wc -l)" -ne 1 ]; then
        echo "The version differs between the build configurations; scripts/version.sh set <version> makes them agree:" >&2
        printf '%s\n' "$versions" | sed "s|^|  $PROJECT: |" >&2
        exit 1
    fi
    builds=$(setting CURRENT_PROJECT_VERSION)
    if [ "$builds" != '$(MARKETING_VERSION)' ]; then
        echo "CURRENT_PROJECT_VERSION must be \$(MARKETING_VERSION), so that the build number is the version," >&2
        echo "which Sparkle compares. Set Current Project Version in the target's Build Settings in Xcode. Now:" >&2
        printf '%s\n' "$builds" | sed "s|^|  $PROJECT: |" >&2
        exit 1
    fi
    echo "$versions"
}

valid() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$' || die "not a version of two or three numbers: $1"
}

set_version() {
    valid "$1"
    sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION = )[^;]*;$/\1$1;/" "$PROJECT"
    [ "$(current)" = "$1" ] || die "the version did not change"
}

case "${1:-}" in
"")
    current
    ;;
check)
    current >/dev/null
    ;;
set)
    [ $# -eq 2 ] || die "usage: scripts/version.sh set <version>"
    set_version "$2"
    echo "$2"
    ;;
next)
    now=$(current)
    heading=$(grep -m 1 '^## ' CHANGELOG.md || true)
    case "$heading" in
    *"(not released yet)") die "CHANGELOG.md already starts a version: $heading" ;;
    esac
    new=${2:-$(echo "$now" | awk -F. '{ $NF = $NF + 1; print }' OFS=.)}
    valid "$new"
    set_version "$new"
    # The new heading goes before the first version's.
    awk -v heading="## $new (not released yet)" \
        '!done && /^## / { print heading; print ""; done = 1 } { print }' CHANGELOG.md >CHANGELOG.md.new
    mv CHANGELOG.md.new CHANGELOG.md
    echo "$new: in $PROJECT and CHANGELOG.md. Commit them (\"Start $new\")."
    ;;
*)
    die "usage: scripts/version.sh [check | set <version> | next [<version>]]"
    ;;
esac
