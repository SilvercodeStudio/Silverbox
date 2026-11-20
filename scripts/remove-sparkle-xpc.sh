#!/bin/sh
# The app target's "Remove Sparkle's XPC services" build phase runs this, after "Record the Git
# commit". Sparkle's XPC services are for a sandboxed app, and Silverbox has no sandbox, so an
# archive (ACTION=install: Product › Archive, make dist) leaves them out, as Sparkle's "Removing
# XPC Services" describes, and signs the framework again for its new contents. Other builds keep
# them; they are never shipped.
#
# The phase needs the target's ENABLE_USER_SCRIPT_SANDBOXING off, as "Record the Git commit" does.
set -eu
[ "${ACTION:-build}" = install ] || exit 0
framework="$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Frameworks/Sparkle.framework"
[ -d "$framework" ] || { echo "error: no Sparkle.framework in the app"; exit 1; }
rm -rf "$framework/Versions/B/XPCServices" "$framework/XPCServices"
codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags,runtime "$framework"
