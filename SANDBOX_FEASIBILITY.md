# Signed App Sandbox feasibility gate

Simulator deletion is deliberately compiled off in version 1 source (`SimulatorFeaturePolicy.deletionEnabled = false`) until every item below succeeds in a production-style signed build. Do not flip this flag based on an unsandboxed Terminal test.

## Test build

1. Use automatic signing with your Apple Developer team and the production bundle ID.
2. Confirm the built entitlements contain only App Sandbox and user-selected read/write access.
3. Test from a separate disposable macOS account with synthetic Xcode folders.

## Evidence checklist

- Select `~/Library/Developer`, relaunch, and verify the bookmark restores access.
- Read Derived Data `info.plist` and `.xcarchive/Info.plist` metadata.
- Calculate allocated size on large and inaccessible fixture trees.
- Move one purpose-created fixture item to Trash and restore it in Finder.
- Run read-only `xcrun simctl list --json` from inside the signed sandboxed app.
- Create one disposable Simulator device, delete only that UDID, and verify no other device changed.
- Archive and validate the same build configuration used for the test.

If `simctl` needs temporary exceptions, private frameworks, Apple Events, automation, Full Disk Access, or a privileged helper, keep both Simulator inventory and deletion inspection-only. Never substitute direct deletion of CoreSimulator folders.

