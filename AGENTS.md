## eXoMAC

This is an emulator front-end for Mac similar to LaunchBox for Windows.
It is oriented towards the eXoDOS project of MS-DOS and Windows 9x games
preservation, in the sense that we can read the eXoDOS / LaunchBox configuration
files to utilize an eXoDOS installation / download, to provide a suitable
client for this collection on the Mac. The actual emulators (DOSBox and related)
are external to this front-end project.

## Prepare for Claude Code

New projects use folder-synchronized groups. When the agent makes a Swift file on disk in the source folder, Xcode adds it to the target automatically. Thus the agent does not need to edit `project.pbxproj`. Tell it not to edit that file by hand.

Give the agent a command-line build so it can check its work. Put this in `CLAUDE.md`:

```
xcodebuild -project MyApp.xcodeproj -scheme MyApp -destination 'platform=macOS' build
```

As an option, connect Claude Code to Xcode's built-in MCP server. This lets the agent build, run tests, and read diagnostics through the open Xcode instance. Enable MCP in Xcode's settings under the Intelligence tab, then register the server with Claude Code:

```
claude mcp add --transport stdio xcode -- xcrun mcpbridge
```

Xcode shows a permission dialog when a new session connects. Click **Allow**.
