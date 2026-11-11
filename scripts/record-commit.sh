#!/bin/sh
# The app target's "Record the Git commit" build phase runs this after Xcode writes the
# built app's Info.plist. It records the commit (scripts/commit-id.sh) as SilverboxCommit,
# for the About window and the reports (AppInfo.commit), and marks an archive (Product ›
# Archive, xcodebuild archive) with SilverboxArchive, so its About window leaves out a
# clean commit, which the release's Git tag names.
#
# The phase needs the target's ENABLE_USER_SCRIPT_SANDBOXING off, because git reads the
# whole working tree, and "Based on dependency analysis" off, so it runs on every build.
set -eu
plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
buddy=/usr/libexec/PlistBuddy
commit=$("$(dirname "$0")/commit-id.sh")
"$buddy" -c "Delete :SilverboxCommit" "$plist" 2>/dev/null || true
[ -z "$commit" ] || "$buddy" -c "Add :SilverboxCommit string $commit" "$plist"
"$buddy" -c "Delete :SilverboxArchive" "$plist" 2>/dev/null || true
[ "${ACTION:-build}" != install ] || "$buddy" -c "Add :SilverboxArchive bool true" "$plist"
